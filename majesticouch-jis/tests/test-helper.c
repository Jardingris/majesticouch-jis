#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>

static CFTypeRef test_product;
static int spawn_count;
static int spawn_error;
static int wait_count;
static int wait_error;
static int child_status;

static CFTypeRef fake_property(IOHIDDeviceRef device, CFStringRef key)
{
    (void)device;
    assert(CFEqual(key, CFSTR(kIOHIDProductKey)));
    return test_product;
}

static int fake_spawn(pid_t *pid, const char *path,
                      const posix_spawn_file_actions_t *actions,
                      const posix_spawnattr_t *attributes,
                      char *const arguments[], char *const environment[])
{
    (void)attributes;
    (void)environment;
    assert(actions == NULL);
    assert(strcmp(path, "/usr/bin/hidutil") == 0);
    assert(strcmp(arguments[0], path) == 0);
    assert(strcmp(arguments[1], "property") == 0);
    assert(strcmp(arguments[2], "--matching") == 0);
    assert(strcmp(arguments[3], "{\"Product\":\"Majestouch Convertible3\"}") == 0);
    assert(strcmp(arguments[4], "--set") == 0);
    assert(strcmp(arguments[5], "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x70000008B,\"HIDKeyboardModifierMappingDst\":0x700000091},{\"HIDKeyboardModifierMappingSrc\":0x70000008A,\"HIDKeyboardModifierMappingDst\":0x700000090}]}") == 0);
    assert(arguments[6] == NULL);
    spawn_count++;
    *pid = 12345;
    return spawn_error;
}

static pid_t fake_wait(pid_t pid, int *status, int options)
{
    assert(pid == 12345);
    assert(options == 0);
    wait_count++;
    if (wait_error != 0) {
        errno = wait_error;
        wait_error = 0;
        return -1;
    }
    *status = child_status;
    return pid;
}

#define IOHIDDeviceGetProperty fake_property
#define posix_spawn fake_spawn
#define waitpid fake_wait
#define main helper_main
#include "../src/majesticouch-jis.c"
#undef main

int main(void)
{
    IOHIDDeviceRef device = (IOHIDDeviceRef)(uintptr_t)1;
    device_connected(NULL, kIOReturnSuccess, NULL, NULL);
    test_product = CFSTR("Apple Magic Keyboard");
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    test_product = NULL;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    test_product = kCFBooleanTrue;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    test_product = CFSTR("Majestouch Convertible3");
    device_connected(NULL, kIOReturnError, NULL, device);
    assert(spawn_count == 0);

    device_connected(NULL, kIOReturnSuccess, NULL, device);
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    assert(spawn_count == 2 && wait_count == 2);
    wait_error = EINTR;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    assert(spawn_count == 3 && wait_count == 4);

    spawn_error = ENOENT;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    assert(wait_count == 4);
    spawn_error = 0;
    child_status = 7 << 8;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    child_status = SIGTERM;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    child_status = 0;
    wait_error = ECHILD;
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    device_connected(NULL, kIOReturnSuccess, NULL, device);
    assert(spawn_count == 8 && wait_count == 8);
    puts("PASS: product guard, exact arguments, repeated events, EINTR, child failure/reaping");
    return 0;
}
