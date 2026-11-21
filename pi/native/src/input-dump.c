// Reads evdev only; does not grab the device or inject events.
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const unsigned keys[] = {BTN_A,BTN_B,BTN_X,BTN_Y,BTN_TL,BTN_TR,BTN_SELECT,BTN_START,BTN_MODE,BTN_THUMBL,BTN_THUMBR};
static const char *names[] = {"A","B","X","Y","LB","RB","VIEW","MENU","XBOX","LS","RS"};
static const unsigned axes[] = {ABS_X,ABS_Y,ABS_RX,ABS_RY,ABS_Z,ABS_RZ,ABS_HAT0X,ABS_HAT0Y};
static const char *axis_names[] = {"LX","LY","RX","RY","LT","RT","DX","DY"};
static long long now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (long long)t.tv_sec*1000+t.tv_nsec/1000000; }
int main(int argc, char **argv) {
    if (argc<2 || argc>3) { fprintf(stderr,"usage: input-dump /dev/input/eventN [seconds=60]\n"); return 2; }
    int seconds=argc==3 ? atoi(argv[2]) : 60;
    if (seconds<1 || seconds>3600) return 2;
    int fd=open(argv[1],O_RDONLY|O_NONBLOCK);
    if (fd<0) { perror("open"); return 1; }
    char name[256]={0}; struct input_id id={0};
    if (ioctl(fd,EVIOCGNAME(sizeof(name)),name)<0 || ioctl(fd,EVIOCGID,&id)<0) { perror("evdev identity"); close(fd); return 1; }
    printf("device=%s id=%04x:%04x\n",name,id.vendor,id.product);
    int values[8]={0}; unsigned char held[sizeof(keys)/sizeof(keys[0])]={0};
    for (unsigned i=0;i<8;i++) { struct input_absinfo a; if (!ioctl(fd,EVIOCGABS(axes[i]),&a)) { values[i]=a.value; printf("%s min=%d max=%d flat=%d\n",axis_names[i],a.minimum,a.maximum,a.flat); } }
    setvbuf(stdout,NULL,_IOLBF,0);
    const long long start=now_ms(), end=start+(long long)seconds*1000;
    int reports=0, sync_dropped=0;
    while (now_ms()<end) {
        struct pollfd p={.fd=fd,.events=POLLIN};
        int left=(int)(end-now_ms()); if (left<0) break;
        int ready=poll(&p,1,left>1000?1000:left);
        if (ready<0) { perror("poll"); close(fd); return 1; }
        if (!ready) continue;
        if (p.revents&(POLLHUP|POLLERR|POLLNVAL)) { fprintf(stderr,"device disconnected\n"); close(fd); return 3; }
        struct input_event e; ssize_t n;
        while ((n=read(fd,&e,sizeof(e)))==(ssize_t)sizeof(e)) {
            if (e.type==EV_SYN && e.code==SYN_DROPPED) { sync_dropped=1; continue; }
            if (sync_dropped) {
                if (e.type==EV_SYN && e.code==SYN_REPORT) { fprintf(stderr,"SYN_DROPPED: restart monitor to resync\n"); close(fd); return 4; }
                continue;
            }
            if (e.type==EV_ABS) for (unsigned i=0;i<8;i++) if (axes[i]==e.code) values[i]=e.value;
            if (e.type==EV_KEY) for (unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++) if (keys[i]==e.code) held[i]=(e.value!=0);
            if (e.type==EV_SYN && e.code==SYN_REPORT) {
                reports++; printf("t=%lldms keys=",now_ms()-start);
                for (unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++) if (held[i]) printf("%s,",names[i]);
                for (unsigned i=0;i<8;i++) printf(" %s=%d",axis_names[i],values[i]);
                putchar('\n');
            }
        }
    }
    printf("reports=%d duration=%ds\n",reports,seconds);
    close(fd); return 0;
}
