// Diagnostic utility: no reset, configuration changes, firmware or detach.
#include <libusb.h>
#include <linux/uinput.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int claim = argc == 2 && !strcmp(argv[1], "--claim");
    int version = 0, fd = open("/dev/uinput", O_RDWR | O_NONBLOCK);
    if (fd < 0) { perror("open uinput"); return 1; }
    if (ioctl(fd, UI_GET_VERSION, &version) < 0) { perror("UI_GET_VERSION"); close(fd); return 1; }
    close(fd);
    printf("uinput protocol version=%d (no virtual device created)\n", version);
    int rc = libusb_init(NULL);
    if (rc) { fprintf(stderr, "init: %s\n", libusb_error_name(rc)); return 1; }
    printf("libusb=%s hotplug=%d\n", libusb_get_version()->describe,
           libusb_has_capability(LIBUSB_CAP_HAS_HOTPLUG));
    libusb_device **list = NULL;
    ssize_t count = libusb_get_device_list(NULL, &list);
    if (count < 0) { fprintf(stderr, "enumerate: %s\n", libusb_error_name((int)count)); libusb_exit(NULL); return 1; }
    int found = 0, failed = 0;
    for (ssize_t i=0; i<count; i++) {
        struct libusb_device_descriptor d;
        if (libusb_get_device_descriptor(list[i], &d)) continue;
        if (d.idVendor != 0x045e || (d.idProduct != 0x02fe && d.idProduct != 0x02e6 && d.idProduct != 0x091e)) continue;
        found++;
        printf("receiver=%04x:%04x bus=%u address=%u\n", d.idVendor, d.idProduct,
               libusb_get_bus_number(list[i]), libusb_get_device_address(list[i]));
        libusb_device_handle *h = NULL;
        rc = libusb_open(list[i], &h);
        if (rc) { fprintf(stderr, "open: %s\n", libusb_error_name(rc)); failed=1; continue; }
        printf("open=OK kernel_driver_active=%d\n", libusb_kernel_driver_active(h, 0));
        if (claim) {
            rc = libusb_claim_interface(h, 0);
            printf("claim_interface=%s\n", libusb_error_name(rc));
            if (!rc) { rc=libusb_release_interface(h, 0); printf("release_interface=%s\n", libusb_error_name(rc)); }
            if (rc) failed=1;
        }
        libusb_close(h);
    }
    libusb_free_device_list(list, 1);
    libusb_exit(NULL);
    if (!found) fprintf(stderr, "Xbox wireless receiver not found\n");
    return !found || failed;
}
