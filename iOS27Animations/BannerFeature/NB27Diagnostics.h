#pragma once
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

/* Bounded geometry/state evidence only. Never log message text, icons or pixels.
 * The file belongs to the current SpringBoard home; no shared global settings. */
static inline void NB27Diagnostic(NSString *event,NSString *detail) {
 static unsigned count;
 if(!NSThread.isMainThread||count>=48)return;count++;
 NSString *line=[NSString stringWithFormat:@"%.3f %@ %@\n",NSDate.date.timeIntervalSince1970,event,detail?:@""];
 NSData *bytes=[line dataUsingEncoding:NSUTF8StringEncoding];if(bytes.length>1536)return;
 NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/NB27Banner.log"];
 int fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC,0600);if(fd<0)return;
 struct stat st;
 if(fstat(fd,&st)==0&&S_ISREG(st.st_mode)&&st.st_size<65536) {
  ssize_t result=write(fd,bytes.bytes,bytes.length);(void)result;
 }
 close(fd);
}
