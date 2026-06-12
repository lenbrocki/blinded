//  Private-framework declarations needed for Apple-Silicon DDC/CI brightness control.
//  Adapted from MonitorControl (MIT License) — see Lumos/Vendor/MonitorControl/NOTICE.md.

#import <Foundation/Foundation.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreGraphics/CoreGraphics.h>

// IOAVService: I2C transport to external displays (exported by IOKit.framework).
typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

// Display info dictionary used to match displays to services (CoreDisplay.framework).
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID);
