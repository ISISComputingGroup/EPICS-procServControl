#!../../bin/windows-x64-debug/isis_example

## You may have to change isis_example to something else
## everywhere it appears in this file

< envPaths

cd ${TOP}

## Register all support components
dbLoadDatabase "dbd/isis_example.dbd"
isis_example_registerRecordDeviceDriver pdbbase

drvAsynIPPortConfigure("port1", "localhost:20000", 100, 0, 0)

## Load record instances
dbLoadRecords("db/isis_example.db", "P=TEST, PORT=port1")

cd ${TOP}/iocBoot/${IOC}
iocInit

seq(procServControl,"P=TEST, PORT=port1")
