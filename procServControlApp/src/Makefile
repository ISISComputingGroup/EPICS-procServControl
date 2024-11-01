TOP=../..

include $(TOP)/configure/CONFIG

# -------------------------------
# Build an Diamond Support Module
# -------------------------------

LIBRARY_IOC += procServControl

# xxxRecord.dbd will be installed into <top>/dbd
DBD += procServControl.dbd

# The following are compiled and added to the support library

# if we need any extra SNC flags add them here
# USR_SNCFLAGS += 

procServControl_SRCS += procServControl.st

procServControl_LIBS += asyn seq

# We need to link against the EPICS Base libraries
procServControl_LIBS += $(EPICS_BASE_IOC_LIBS)
procServControl_SYS_LIBS_WIN32 += Userenv

include $(TOP)/configure/RULES
