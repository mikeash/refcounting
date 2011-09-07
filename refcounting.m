// gcc -framework Foundation --std=c99 refcounting.m

#import <Foundation/Foundation.h>


static CFMutableDictionaryRef gRefcountDict;
static OSSpinLock gRefcountDictLock;

static uintptr_t GetRefcount(void *key)
{
    if(!gRefcountDict)
        return 1;
    
    const void *value;
    if(!CFDictionaryGetValueIfPresent(gRefcountDict, key, &value))
        return 1;
    
    return (uintptr_t)value;
}

static void SetRefcount(void *key, uintptr_t count)
{
    if(count <= 1)
    {
        if(gRefcountDict)
            CFDictionaryRemoveValue(gRefcountDict, key);
    }
    else
    {
        if(!gRefcountDict)
            gRefcountDict = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        CFDictionarySetValue(gRefcountDict, key, (void *)count);
    }
}

static void IncrementRefcount(void *key)
{
    OSSpinLockLock(&gRefcountDictLock);
    uintptr_t count = GetRefcount(key);
    SetRefcount(key, count + 1);
    OSSpinLockUnlock(&gRefcountDictLock);
}

static uintptr_t DecrementRefcount(void *key)
{
    OSSpinLockLock(&gRefcountDictLock);
    uintptr_t count = GetRefcount(key);
    uintptr_t newCount = count - 1;
    SetRefcount(key, newCount);
    OSSpinLockUnlock(&gRefcountDictLock);
    
    return newCount;
}

@interface NSObject (MARefcounting)

- (id)ma_retain;
- (void)ma_release;

@end

@implementation NSObject (MARefcounting)

- (id)ma_retain
{
    IncrementRefcount(self);
    return self;
}

- (void)ma_release
{
    uintptr_t newCount = DecrementRefcount(self);
    if(newCount == 0)
        [self dealloc];
}

@end


@interface TestClass : NSObject {
@public
    int count;
}
@end
@implementation TestClass
- (void)dealloc
{
    fprintf(stderr, "TestClass instance %p dealloc\n", self);
    [super dealloc];
}
@end

int main(int argc, char **argv)
{
    for(int i = 0; i < 10; i++)
    {
        CFMutableArrayRef array = CFArrayCreateMutable(NULL, 0, NULL);
        
        for(int i = 0; i < 10000; i++)
        {
            TestClass *obj = [[TestClass alloc] init];
            CFArrayAppendValue(array, obj);
            obj->count = random() % 10;
            for(int j = 0; j < obj->count; j++) 
                [obj ma_retain];
        }
        
        while(CFArrayGetCount(array))
        {
            CFIndex count = CFArrayGetCount(array);
            CFIndex index = random() % count;
            TestClass *obj = (id)CFArrayGetValueAtIndex(array, index);
            
            int refcount = obj->count + 1;
            while(refcount-- > 0)
                [obj ma_release];
            
            CFArrayRemoveValueAtIndex(array, index);
        }
        
        
        CFRelease(array);
    }
}

