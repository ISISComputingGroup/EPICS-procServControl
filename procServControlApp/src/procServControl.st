program procServControl("P=P")

%% #include <stdio.h>
%% #include <stdlib.h>
%% #include <string.h>
%% #include <epicsMutex.h>
#ifdef _WIN32
%% #include <windows.h>
%% #include <process.h>
%% #include <processthreadsapi.h>
%% #include <userenv.h>
#else
%% #include <unistd.h>
#endif /* ifdef _WIN32 */
option +r;

/* This defines the number of lines and max line length */
#define LINELENGTH 256
#define NLINES 20

/* This is LINELENGTH*NLINES. It must match NELM on the IOCOUT and
 * PROCOUT waveform records */
#define NELM 5120

/* Inputs */
string port;            assign port            to "{P}:PORT";
int showout;            assign showout        to "{P}:SHOWOUT.VAL"; monitor showout;

/* Outputs */
string iocname;            assign iocname        to "{P}:IOCNAME";
int autorestart;        assign autorestart    to "{P}:AUTORESTART";
int status;                assign status        to "{P}:STATUS";
#define RUNNING 0
#define SHUTDOWN 1
#define PROCSERVSTOPPED 2
#define INVALIDPORTNAME 3
char iocout[NELM];        assign iocout        to "{P}:IOCOUT";

/* Commands */
int start;                assign start         to "{P}:START";
int stop;                assign stop         to "{P}:STOP";
int restart;            assign restart         to "{P}:RESTART";
int toggle;                assign toggle         to "{P}:TOGGLE";

/* Flags */
monitor start;            evflag startMon;    sync start startMon;
monitor stop;            evflag stopMon;        sync stop stopMon;
monitor restart;        evflag restartMon;    sync restart restartMon;
monitor toggle;            evflag toggleMon;    sync toggle toggleMon;
monitor status;            evflag statusMon;    sync status statusMon;

/* Internal variables for storing output lines*/
char iocLine[NLINES][LINELENGTH];
int iocLineI;
int lastcommand;
#define NONE 0
#define IOCOUT 1
#define AUTORESTART 2
#define IOCNAME 3
#define STATUS 4

/* These are needed to tie up the ppasynUser with the state machine */
int stateIndex;

/* have we launched a procServ */
int procserv_launched;

/* we define two ports per ioc in build_ioc_startup, between ports 20000 and 49152
 * (port 49152 is start of IANA dynamic range for port allocation)
 * Therefore we can have at most ((49152 - 20000)/2) (=14576) iocs assuming all ports are free
 * Set max state machines at 10,000 to leave some room for ports which are in use.
 */
#define NSTATEMACHINES 10000
%% static int stateIndexGlobal = 0;

/* C functions and asyn things */
%% #include <asynOctetSyncIO.h>
%% static asynUser* pasynUsers[NSTATEMACHINES];
%% static void createAsynUser(struct UserVar *pVar);
%% static void startProcserv(struct UserVar *pVar);
%% static void getNextLine(struct UserVar *pVar);
%% static void writeControlChar(struct UserVar *pVar, const char *controlChar);
%% static epicsMutexId procsrvLaunchLock = NULL;
%% static epicsThreadOnceId onceId = EPICS_THREAD_ONCE_INIT;
%% static void procsrvLaunchLockInit(void *arg);

ss ssUserInput {
    state INIT {
        entry {
            %% epicsThreadOnce(&onceId, &procsrvLaunchLockInit, NULL);
        }

        when() {
            /* Clear all event flags */
            efClear(startMon);
            efClear(stopMon);
            efClear(restartMon);
            efClear(toggleMon);
            efClear(statusMon);
        } state MONITORINPUTS
    }

    state MONITORINPUTS {

        entry {
        }

        when( (status == PROCSERVSTOPPED) && (procserv_launched == 0) && (
                (efTest(startMon) && (start == 1)) ||
                (efTest(stopMon) && (stop == 1)) ||
                (efTest(restartMon) && (restart == 1)) ||
                (efTest(toggleMon) && (toggle == 1)) ) ) {
            startProcserv(pVar);
            procserv_launched = 1;
        } state MONITORINPUTS

        when((status != PROCSERVSTOPPED) && efTestAndClear(startMon) && (start == 1)) {
            /* If we are shutdown then send CTRL-X to start */
            if (status == SHUTDOWN) {
                %% writeControlChar(pVar, "\x18");
            }
            start = 0;
            pvPut(start); /* not using SYNC as Busy record */
            efSet(statusMon); /* to avoid timeout if start when running */
        } state WAITFORRUNNING

        when((status != PROCSERVSTOPPED) && efTestAndClear(stopMon) && (stop == 1)) {
            /* If we are running, then make sure autorestart is off, if it isn't
             * send CTRL-T, then send CTRL-X to stop */
            if (status == RUNNING) {
                if (autorestart == 1) {
                    autorestart = 0;
                    pvPut(autorestart, SYNC);
                    %% writeControlChar(pVar, "\x14");
                }
                %% writeControlChar(pVar, "\x18");
            }
            stop = 0;
            pvPut(stop);  /* not using SYNC as Busy record */
            efSet(statusMon); /* to avoid timeout if stop when stopped */
        } state WAITFORSHUTDOWN

        when((status == RUNNING) && efTestAndClear(restartMon) && (restart == 1)) {
            /* If we are running, then make sure autorestart is on, if it isn't
             * send CTRL-T, then send CTRL-X to restart */
            if (autorestart == 0) {
                autorestart = 1;
                pvPut(autorestart, SYNC);
                %% writeControlChar(pVar, "\x14");
            }
            %% writeControlChar(pVar, "\x18");
            restart = 0;
            pvPut(restart);  /* not using SYNC as Busy record */
            efSet(statusMon); /* to avoid potential timeout error */
        } state WAITFORRESTART

        when((status == SHUTDOWN) && efTestAndClear(restartMon) && (restart == 1)) {
            /* send CTRL-X to restart */
            printf("DEBUG: doing restart from SHUTDOWN for %s\n", macValueGet("P"));
            %% writeControlChar(pVar, "\x18");
            restart = 0;
            pvPut(restart);  /* not using SYNC as Busy record */
            efSet(statusMon); /* to avoid potential timeout error */
        } state WAITFORRUNNING

        when((status != PROCSERVSTOPPED) && efTestAndClear(toggleMon) && (toggle == 1)) {
            /* If we are running, then send CTRL-T to toggle autorestart */
            if (status == RUNNING) {
                autorestart = !autorestart; /* update local value in case of delay from parsing status */
                pvPut(autorestart, SYNC);
                %% writeControlChar(pVar, "\x14");
            } else {
                printf("DEBUG: ignoring toggle as not running for %s\n", macValueGet("P"));
            }
            toggle = 0;
            pvPut(toggle);  /* not using SYNC as Busy record */
        } state MONITORINPUTS
    }
    
    state WAITFORSHUTDOWN {
        entry {
        }
        
        when(efTestAndClear(statusMon) && (status == SHUTDOWN)) {
        } state MONITORINPUTS

        when(delay(5.0)) {
            printf("WARNING: Timeout waiting for SHUTDOWN of %s\n", macValueGet("P"));
        } state MONITORINPUTS
    }

    state WAITFORRESTART {
        entry {
        }
        
        when(efTestAndClear(statusMon) && (status == SHUTDOWN)) {
        } state WAITFORRUNNING

        when(delay(5.0)) {
            printf("WARNING: Timeout waiting for RESTART of %s\n", macValueGet("P"));
        } state MONITORINPUTS
    }

    state WAITFORRUNNING {
        entry {
        }
        
        when(efTestAndClear(statusMon) && (status == RUNNING)) {
        } state MONITORINPUTS

        /* the default procserv delay between a stop and start when a restart is signalled is 15 seconds */
        when(delay(30.0)) {
            printf("WARNING: Still waiting for RUNNING (autorestart = %s) - resending start for %s\n",
                       (autorestart != 0 ? "ON" : "OFF"), macValueGet("P"));
            %% writeControlChar(pVar, "\x18");
        } state WAITFORRUNNING2
    }

    state WAITFORRUNNING2 {
        entry {
        }

        when(efTestAndClear(statusMon) && (status == RUNNING)) {
        } state MONITORINPUTS

        when(delay(20.0)) {
            printf("ERROR: Timeout waiting for RUNNING of %s (autorestart = %s)\n",
                macValueGet("P"), (autorestart != 0 ? "ON" : "OFF"));
        } state MONITORINPUTS
    }
}

ss ssProcServInput {
    state INIT {
        entry {
        }

        when() {
            /* Get the asyn port name */
            pvGet(port, SYNC);
            /* Connect the asyn port */
            %% createAsynUser(pVar);
        } state MONITORINPUTS
    }

    state MONITORINPUTS {

        entry {
        }

        when() {
            /* This sets lastcommand state */
            %% getNextLine(pVar);
        } state PROCESSINPUT
    }

    state PROCESSINPUT {
        entry {
        }

        when(lastcommand == NONE) {
        } state MONITORINPUTS

        when(lastcommand == IOCOUT) {
            pvPut(iocout, SYNC);
        } state MONITORINPUTS

        when(lastcommand == AUTORESTART) {
            pvPut(autorestart, SYNC);
            pvPut(iocout, SYNC);
        } state MONITORINPUTS

        when(lastcommand == IOCNAME) {
            pvPut(iocname, SYNC);
            pvPut(iocout, SYNC);
        } state MONITORINPUTS

        when(lastcommand == STATUS) {
            pvPut(status, SYNC);
            pvPut(iocout, SYNC);
        } state MONITORINPUTS
    }
}

/* C functions */
%{

static void do_sleep(float secs)
{
#ifdef _WIN32
    Sleep((int)(1000 * secs));
#else
    sleep(secs);
#endif /* ifdef _WIN32 */
}

/* Create an asynUser and set it up using the port name */
static void createAsynUser(struct UserVar *pVar) {
    int i;
    asynUser *pasynUser = NULL;
    /* Increment the global state machine counter */
    pVar->stateIndex = stateIndexGlobal++;
    if (stateIndexGlobal > NSTATEMACHINES) {
        printf("***Error: too many procServ state machines defined\n");
        return;
    }
    /* Connect the port */
    if (pasynOctetSyncIO->connect(pVar->port, 0, &pasynUser, NULL)) {
        /* Invalid port name, can't recover from this */
        printf("***Error: can't connect to asyn port name %s\n", pVar->port);
        pasynUser = NULL;
    } else {
        pasynOctetSyncIO->setInputEos(pasynUser, "\r\n", 2);
        pasynOctetSyncIO->setOutputEos(pasynUser, "", 0);
        pasynUsers[pVar->stateIndex] = pasynUser;
        /* Clear output lines */
        for (i = 0; i < NLINES; i++) {
            strcpy(pVar->iocLine[i], "");
        }
        pVar->iocLineI = 0;
    }
}

/* Get the next line of IOC output and process it */
static void getNextLine(struct UserVar *pVar) {
    char buffer[LINELENGTH];
    char temp[LINELENGTH];
    size_t bytes = 0;
    int eomReason;
    int i, index, yesNo;
    asynUser *pasynUser;

    /* By default there is nothing to do on return */
    pVar->lastcommand = NONE;

    /* Check that asynUser exists */
    if (pVar->stateIndex >= NSTATEMACHINES) return;
    pasynUser = pasynUsers[pVar->stateIndex];
    if (pasynUser == NULL) {
        if (pVar->status == INVALIDPORTNAME) {
            /* we can never recover, but at least we won't use all the CPU... */
            do_sleep(1);
        } else {
            pVar->lastcommand = STATUS;
            pVar->status = INVALIDPORTNAME;
        }
        return;
    }
    
    /* Check asynUser is connected */
    pasynManager->isConnected(pasynUser, &yesNo);
    
    if (yesNo == 0) {
        if (pVar->status == PROCSERVSTOPPED) {
            do_sleep(1);
        } else {
            pVar->status = PROCSERVSTOPPED;
            pVar->lastcommand = STATUS;
        }
        return;
    } else if (pVar->status == PROCSERVSTOPPED) {
        /* need to set the right eos if the port has just connected */
        pasynOctetSyncIO->setInputEos(pasynUser, "\r\n", 2);
        pasynOctetSyncIO->setOutputEos(pasynUser, "", 0);
        /* Note we don't set lastcommand as the status is just being used as
         * a flag so we don't set Eos many times. If it has just connected
         * procServ will tell us the status in 4 lines time anyway... */
        pVar->status = SHUTDOWN;
    }

    /* zero buffer, guarantees termination if we only read LINELENGTH-1 chars */
    memset(buffer, 0, LINELENGTH);

    /* read from the asyn port, if we fail (no data) just return */
    if ( pasynOctetSyncIO->read(pasynUser, buffer, LINELENGTH-1, 0.1, &bytes, &eomReason) || (bytes == 0) ) {
        do_sleep(0.1f);
        return;
    }

    /* put buffer in the right place */
    strcpy(pVar->iocLine[pVar->iocLineI], buffer);
    pVar->iocLineI = (pVar->iocLineI + 1) % NLINES;

    /* If we are told to show the result, copy the lines in the right order to
     * iocout */
    if (pVar->showout) {
        bytes = 0;
        /* Start with the line after the one just written (the oldest line) */
        for (i = 0; i < NLINES; i++) {
            index = (pVar->iocLineI + i)%NLINES;
            strcpy(pVar->iocout + bytes, pVar->iocLine[index]);
            bytes += strlen(pVar->iocLine[index]);
            /* Join with a \n */
            sprintf(pVar->iocout + bytes++, "\n");
        }
        /* zero out rest of array so we do not get any leftovers displayed */
        if ( bytes < sizeof(pVar->iocout) ) {
              memset(pVar->iocout + bytes, 0, sizeof(pVar->iocout) - bytes);
        }
        pVar->lastcommand = IOCOUT;
    }

    /* If it was a procServ command, parse it */
    if (buffer[0] == '@' && buffer[1] == '@' && buffer[2] == '@') {
        /*printf("%s: {%s}\n", pVar->port, buffer);*/
        /* grab ioc name */
        if (sscanf(buffer, "@@@ Child \"%s started as: %s", pVar->iocname, temp) == 2) {
            pVar->iocname[strlen(pVar->iocname)-1] = '\0';
            pVar->lastcommand = IOCNAME;
            /*printf("iocname: %s\n", pVar->iocname);*/
            return;
        }
        /* grab current status */
        if (sscanf(buffer, "@@@ Child \"%*s %s", temp)) {
            if (strcmp(temp, "PID:") == 0) {
                pVar->status = RUNNING;
            } else if (strcmp(temp, "is") == 0) {
                pVar->status = SHUTDOWN;
            } else {
                /*printf("status (invalid): %s\n", temp);*/
                return;
            }
            /*printf("status (1): (%s) %d\n", temp, pVar->status);*/
            pVar->lastcommand = STATUS;
            return;
        }
        if (sscanf(buffer, "@@@ Restarting child %s", temp)) {
            pVar->lastcommand = STATUS;
               pVar->status = RUNNING;
            /*printf("status (2): %d\n", pVar->status);*/
            return;
        }
        if (sscanf(buffer, "@@@ Child process is shutting %s", temp)) {
            pVar->lastcommand = STATUS;
               pVar->status = SHUTDOWN;
            /*printf("status (3): %d\n", pVar->status);*/
            return;
        }
        /* grab current autorestart */
        if (sscanf(buffer, "@@@ Toggled auto restart to %s", temp)) {
            pVar->lastcommand = AUTORESTART;
            if (strcmp(temp, "ON") == 0) {
                pVar->autorestart = 1;
            } else {
                pVar->autorestart = 0;
            }
            /*printf("autorestart (1): %d\n", pVar->autorestart);*/
            return;
        }
        if (sscanf(buffer, "@@@ Use ^X to kill the child, auto restart is %s", temp)) {
            pVar->lastcommand = AUTORESTART;
            if (strcmp(temp, "ON,") == 0) {
                pVar->autorestart = 1;
            } else {
                pVar->autorestart = 0;
            }
            /*printf("autorestart (2): %d\n", pVar->autorestart);*/
            return;
        }
    }
}

/* Write a control char to procServ */
static void writeControlChar(struct UserVar *pVar, const char *controlChar) {
    size_t bytes;
    int yesNo;
    asynUser *pasynUser;

    /* Check that asynUser exists */
    if (pVar->stateIndex >= NSTATEMACHINES) return;
    pasynUser = pasynUsers[pVar->stateIndex];
    if (pasynUser == NULL) return;

    /* Check asynUser is connected */
    pasynManager->isConnected(pasynUser, &yesNo);
    if (yesNo == 0) return;

    /* Write control char to procServ */
    pasynOctetSyncIO->write(pasynUser, controlChar, 1, 1.0, &bytes);
}

static void procsrvLaunchLockInit(void *arg)
{
    procsrvLaunchLock = epicsMutexMustCreate();
}

static double getEnvDoubleValue(const char* var, double default_value)
{
    const char* env_value = getenv(var);
    return env_value != NULL ? atof(env_value) : default_value;
}

/* start procserv. We do not want to inherit the process environment
   as we are spawned from procServControl ioc and its environment can
   confuse the ioc we create, hence the slightly convoluted process creation
   to not inherit process variables but try to inherit user/system ones
*/
static void startProcserv(struct UserVar *pVar) {
    asynUser *pasynUser;
    const char* epics_kit_root = getenv("EPICS_KIT_ROOT");
    char command[256];
    int i, yesNo;
     /* second to wait after launch before try autoconnect, if does not initially
        connect it may be 20 seconds before retry */
    const double CONNECT_INITIAL_WAIT = getEnvDoubleValue("CONNECT_INITIAL_WAIT", 2.0); /* make long enough to hopefully auto-connect on first try */
    const double CONNECT_CHECK_WAIT = getEnvDoubleValue("CONNECT_CHECK_WAIT", 0.5);
    const double CONNECT_TOTAL_WAIT = getEnvDoubleValue("CONNECT_TOTAL_WAIT", 25.0); /* at least 20 seconds to be greater than default asyn DEFAULT_SECONDS_BETWEEN_PORT_CONNECT */
    const double LAUNCH_WAIT = getEnvDoubleValue("LAUNCH_WAIT", 0.2); /* time to hold global procServ launch lock for */
#ifdef _WIN32
    const char* comspec = getenv("ComSpec");
    LPVOID lpEnv = NULL;
    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    BOOL status;
    DWORD dwCreationFlags = 0;
    ZeroMemory( &si, sizeof(si) );
    si.cb = sizeof(si);
    ZeroMemory( &pi, sizeof(pi) );
    if (epics_kit_root != NULL) {
        epicsSnprintf(command, sizeof(command), "\"%s\" /c \"%s\\iocstartup\\ioc_bats\\%s.bat\"", comspec, epics_kit_root, pVar->port);
        printf("startProcserv: Running %s\n", command);
        if (!CreateEnvironmentBlock(&lpEnv, GetCurrentProcessToken(), FALSE)) {
            printf("startProcserv: Cannot create environment: error 0x%08x\n", GetLastError());
            return;
        }
        dwCreationFlags |= CREATE_UNICODE_ENVIRONMENT; /* CreateEnvironmentBlock returns unicode */
        /* use lock and sleep to stop too many simultaneous procserv launches that looks like it may cause issues */
        epicsMutexLock(procsrvLaunchLock);
        status = CreateProcess(NULL, command, NULL, NULL, FALSE, dwCreationFlags, lpEnv, NULL, &si, &pi);
        if (!status) {
            printf("startProcserv: Cannot create process for %s: error 0x%08x\n", pVar->port, GetLastError());
        }
        epicsThreadSleep(LAUNCH_WAIT);
        epicsMutexUnlock(procsrvLaunchLock);
        DestroyEnvironmentBlock(lpEnv);
        if (!status) {
            return;
        }
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);

        /* Check that asynUser exists */
        if (pVar->stateIndex >= NSTATEMACHINES) {
            printf("startProcserv: ERROR: stateIndex >= NSTATEMACHINES\n");
            return;
        }
        pasynUser = pasynUsers[pVar->stateIndex];
        if (pasynUser == NULL) {
            printf("startProcserv: ERROR: pasynUser is NULL\n");
            return;
        }
        /* enable autoconnect now we have launched procserv */
        epicsThreadSleep(CONNECT_INITIAL_WAIT);
        pasynManager->autoConnect(pasynUser, 1);
        yesNo = 0;
        /* need to wait up to 20 seconds as default asyn connect retry */
        for(i=0; !yesNo && i< (int)(CONNECT_TOTAL_WAIT / CONNECT_CHECK_WAIT); ++i) {
            epicsThreadSleep(CONNECT_CHECK_WAIT);
            pasynManager->isConnected(pasynUser, &yesNo);
        }
        if (yesNo == 1) {
            printf("startProcserv: %s connected after %f seconds\n", pVar->port, CONNECT_INITIAL_WAIT + CONNECT_CHECK_WAIT * i);
        } else {
            printf("startProcserv: WARNING: %s not yet connected after %f seconds\n", pVar->port, CONNECT_INITIAL_WAIT + CONNECT_CHECK_WAIT * i);
        }
    } else {
        printf("startProcserv: WARNING: EPICS_KIT_ROOT not defined\n");
    }
#endif
}

}%
