#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>

#define PRODUCT_NAME "Majestouch Convertible3"

extern char **environ;

static void log_message(const char *format, ...)
{
    time_t now = time(NULL);
    struct tm local_time;
    char timestamp[32] = "unknown-time";
    if (localtime_r(&now, &local_time) != NULL) {
        (void)strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S%z", &local_time);
    }
    fprintf(stderr, "%s majesticouch-jis: ", timestamp);
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
}

static bool matches_product(IOHIDDeviceRef device)
{
    if (device == NULL) {
        return false;
    }
    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    return product != NULL && CFGetTypeID(product) == CFStringGetTypeID() &&
           CFEqual(product, CFSTR(PRODUCT_NAME));
}

static void device_connected(void *context, IOReturn result, void *sender,
                             IOHIDDeviceRef device)
{
    (void)context;
    (void)sender;
    if (result != kIOReturnSuccess) {
        log_message("matching callback failed: 0x%08x", (unsigned int)result);
        return;
    }
    if (!matches_product(device)) {
        return;
    }

    char *arguments[] = {
        "/usr/bin/hidutil", "property", "--matching",
        "{\"Product\":\"" PRODUCT_NAME "\"}", "--set",
        "{\"UserKeyMapping\":["
        "{\"HIDKeyboardModifierMappingSrc\":0x70000008B,"
        "\"HIDKeyboardModifierMappingDst\":0x700000091},"
        "{\"HIDKeyboardModifierMappingSrc\":0x70000008A,"
        "\"HIDKeyboardModifierMappingDst\":0x700000090}]}", NULL
    };
    pid_t child;
    int error = posix_spawn(&child, arguments[0], NULL, NULL, arguments, environ);
    if (error != 0) {
        log_message("hidutil spawn failed: %s", strerror(error));
        return;
    }

    int status;
    pid_t waited;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited == -1 && errno == EINTR);
    if (waited == -1) {
        log_message("hidutil wait failed: %s", strerror(errno));
    } else if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        log_message("connected: %s; hidutil exit=0", PRODUCT_NAME);
    } else if (WIFEXITED(status)) {
        log_message("hidutil exit=%d", WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        log_message("hidutil terminated by signal %d", WTERMSIG(status));
    } else {
        log_message("hidutil unexpected status=0x%x", (unsigned int)status);
    }
}

static void device_removed(void *context, IOReturn result, void *sender,
                           IOHIDDeviceRef device)
{
    (void)context;
    (void)sender;
    if (result == kIOReturnSuccess && matches_product(device)) {
        log_message("disconnected: %s", PRODUCT_NAME);
    }
}

static void catch_signal(int number)
{
    (void)number;
    /* A caught disposition lets dispatch observe it; spawned hidutil gets SIG_DFL. */
}

static void stop_run_loop(void *context)
{
    (void)context;
    CFRunLoopStop(CFRunLoopGetMain());
}

static dispatch_source_t termination_source(int number)
{
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
        (uintptr_t)number, 0, dispatch_get_main_queue());
    if (source == NULL) {
        return NULL;
    }
    struct sigaction action = {0};
    action.sa_handler = catch_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(number, &action, NULL) != 0) {
        dispatch_source_cancel(source);
        dispatch_resume(source);
        dispatch_release(source);
        return NULL;
    }
    dispatch_source_set_event_handler_f(source, stop_run_loop);
    dispatch_resume(source);
    return source;
}

int main(void)
{
    dispatch_source_t term = termination_source(SIGTERM);
    dispatch_source_t interrupt = termination_source(SIGINT);
    if (term == NULL || interrupt == NULL) {
        log_message("cannot register termination signals");
        return EXIT_FAILURE;
    }

    /* Enumeration only: do not open, seize, or schedule devices for input. */
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault,
        kIOHIDManagerOptionIndependentDevices);
    if (manager == NULL) {
        log_message("cannot create HID manager");
        return EXIT_FAILURE;
    }
    const void *keys[] = {CFSTR(kIOHIDProductKey)};
    const void *values[] = {CFSTR(PRODUCT_NAME)};
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, keys, values,
        1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (matching == NULL) {
        log_message("cannot create matching dictionary");
        CFRelease(manager);
        return EXIT_FAILURE;
    }

    IOHIDManagerRegisterDeviceMatchingCallback(manager, device_connected, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, device_removed, NULL);
    IOHIDManagerSetDeviceMatching(manager, matching);
    CFRelease(matching);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    log_message("watching: %s (device notifications only)", PRODUCT_NAME);
    CFRunLoopRun();

    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    CFRelease(manager);
    dispatch_source_cancel(term);
    dispatch_source_cancel(interrupt);
    dispatch_release(term);
    dispatch_release(interrupt);
    log_message("stopped");
    return EXIT_SUCCESS;
}
