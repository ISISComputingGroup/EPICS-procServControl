/* This file was automatically generated on Tue 04 Sep 2012 11:56:22 BST from
 * source: /dls_sw/prod/R3.14.11/support/procServControl/1-2/etc/makeIocs/example.xml
 * 
 * *** Please do not edit this file: edit the source file instead. ***
 *  */
#include "epicsExit.h"
#include "epicsThread.h"
#include "iocsh.h"

int main(int argc, char *argv[])
{
    if(argc>=2) {
        iocsh(argv[1]);
        epicsThreadSleep(.2);
    }
    iocsh(NULL);
    epicsExit(0);
    return 0;
}
