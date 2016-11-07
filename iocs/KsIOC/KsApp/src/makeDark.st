program makeDark ( "A=SIM:Qi2" )
#define MAKE_DARK_VERSION 2.1
/**************************************************************************************************
 *	Program to start master offset frame acquisition sequence for DS-Qi2.
 *
 *	by Alireza Panna, NIH/NHLBI/IPL
 *	10 October, 2015
 *
 *	#  A    	= prefix for all the PV's associatd with the camera ioc.
 *  
 *  __log__ 	= 10/12/2015: (AP) Version 1.0 created
 *				= 10/14/2015: (AP) single shot sequence has a follow up sequence option for 
 *						  	   	   acquiring reference images if the START_REFERENCE PV is checked
 *				= 10/14/2015: (AP) fixed error in single shot sequence final state transition which
 *						   	   	   was enabling the save background pv.	
 *				= 10/15/2015: (AP) added abort functionality for dark field sequence, offset frame
 *								   filenames are automatically generated as "dark_yymmdd_hhmm"
 *								   Reference frame filenames are automatically set to "reference"
 *								   Changed version to 1.4.
 *				= 10/19/2015: (AP) sample Y motor movement is tested using DMOV to wait until it is
 *								   out of the way for reference shots. If background correction is 
 *								   enabled, then single shot and reference filenames are prepended 
 *								   with "DFCOR"
 *				= 10/20/2015: (AP) changed STATUS record to STATUS_STRING so it doesn't clash with the 
 *								   procServ STATUS record. 
 *				= 12/31/2015: (AP) removed single shot sequence from here and renamed program to
 *								   makeDark.st. Updated to version 2.0
 *				= 01/03/2016: (AP) improved functionality, added error checks, removed scan record 
 *								   dependence. Completely re-worked.
 *				= 03/05/2016: (AP) Disable the $(P)$(R)EnableFlatField PV when acquiring master 
 *								   offset frame. Update version to 2.1
 *	__to-do__  	= 			  	
 ****************************************************************************************************/ 

/*===========================Option statements========================*/
option +r; /* allows running more than one copy with different macros */
option -c; /* dont wait for channel connections*/
option -l; /* use C line numbers in error messages etc. */
option +d; /* Turn on run time debug messages */
option +w; /* Suppress snc compiler warnings */
option -s; /* dont run in safe mode */

#include "seqPVmacros.h"
/* Escape to C code for C includes using %% */
%% #include <string.h>
%% #include <epicsThread.h>
%% #include <epicsTime.h>
%% #include <tsDefs.h>

#if defined(_WIN32)
%% #include <Windows.h>
#endif
#if defined(__unix__) || defined(__unix) || defined(unix)
%% #include <unistd.h>								      // POSIX flags 
%% #include <time.h>								      // clock_gettime(), time()
%% #include <sys/time.h>					 
#endif

/* 0 long */
#ifndef NULL
#define NULL 0L
#endif

/*=========================================assignments/declarations===================================================*/
PV (short,  	offsetStart,  			"{A}:START_OFFSET",					EvFlag);		/* start dark sequence */
PV (string, 	statusMsg,  	   		"{A}:OFFSET_STATUS",				NoMon);			/* for status message string */
PV (string, 	darkDate,  	   			"{A}:OFFSET_DATE",					NoMon);			/* for dark field date tag */
PV (double, 	offsetMeanRBV,  	   	"{A}:OFFSET_MEAN_RBV",				NoMon);			/* master offset frame mean counts */
PV (short,  	autoSave,				"{A}:TIFF1:AutoSave", 				NoMon);			/* tiff autosave */
PV (short,  	inc,					"{A}:TIFF1:AutoIncrement", 			NoMon);			/* tiff increment */
PV (short,		stats1Callbacks,		"{A}:Stats1:EnableCallbacks",		NoMon);			/* stats1 callbacks */
PV (short,		stats1ArrayCallbacks,	"{A}:Stats1:ArrayCallbacks",		NoMon);			/* stats1 array callbacks */
PV (short,		stats1ComputeStat,		"{A}:Stats1:ComputeStatistics",		NoMon);			/* stats1 compute statistics */
PV (double,		stats1ArrayMeanRBV,		"{A}:Stats1:MeanValue_RBV",			NoMon);			/* stats1 array mean value */
PV (short,  	processCallbacks,		"{A}:Proc1:EnableCallbacks", 		NoMon);			/* process callbacks */
PV (short,  	processArrayCallbacks,	"{A}:Proc1:ArrayCallbacks", 		NoMon);			/* process array callbacks */
PV (short,  	filterCallbacks, 		"{A}:Proc1:FilterCallbacks", 		NoMon);			/* Filter callbacks */
PV (double, 	numFilter,   			"{A}:Proc1:NumFilter", 				Monitor);		/* How many frames to filter */
PV (double, 	numFilteredRBV,  		"{A}:Proc1:NumFiltered_RBV", 		Monitor);		/* Number of filtered frames */
PV (short,  	enableFilter,    		"{A}:Proc1:EnableFilter", 			NoMon);			/* Enable Filter plugin */
PV (short,  	filterType,    			"{A}:Proc1:FilterType", 			NoMon);			/* What is the filter type */
PV (double, 	scale,    				"{A}:Proc1:OScale", 				NoMon);			/* scale factor */
PV (short,  	dataType,    			"{A}:Proc1:DataTypeOut", 			NoMon);			/* image data type */
PV (short,  	resetFilter,     		"{A}:Proc1:ResetFilter", 			NoMon);			/* Reset filter */
PV (short,  	autoResetFilter,    	"{A}:Proc1:AutoResetFilter", 		NoMon);			/* Auto Reset filter */
PV (short,  	enableBackground,		"{A}:Proc1:EnableBackground", 		NoMon);			/* Enable background correction */
PV (short,  	enableFlatField,		"{A}:Proc1:EnableFlatField", 		NoMon);			/* Enable flat field  correction */
PV (short,  	validOffsetRBV,  		"{A}:Proc1:ValidBackground_RBV",	EvFlag);		/* check if offset frame is valid */
PV (short,  	saveBackground,			"{A}:Proc1:SaveBackground", 		NoMon);			/* Save background correction */
PV (short,  	trigger,    			"{A}:cam1:NikonTriggerMode", 		Monitor);		/* set the trigger 0 for live, 1 for hard */
PV (short,  	acquire,    			"{A}:cam1:Acquire", 				Monitor);		/* acquire image set */
PV (double, 	numImages,   			"{A}:cam1:NumImages", 				NoMon);			/* How many images to acquire */
PV (double, 	numImagesRBV,   		"{A}:cam1:NumImagesCounter_RBV",	NoMon);
PV (double, 	imageMode,   			"{A}:cam1:ImageMode", 				NoMon);			/* qi2 image mode=>single, multiple, continous */
PV (double, 	acquireTime,   			"{A}:cam1:AcquireTime", 			NoMon);
PV (double,  	arrayRate,				"{A}:image1:ArrayRate_RBV", 		Monitor);		/* array rate */

char   tiffName[256];
assign tiffName to "{A}:TIFF1:FileName";

%% long mytime;
%% string tempName;
%% struct tm *tm1;

/*====================State Sets====================*/
ss makeDark
{
	state init {
		
		when (pvConnectCount() < pvChannelCount()) {
			PVPUTSTR(statusMsg, "OFFLINE");
		} state init
		
		when (pvConnectCount() == pvChannelCount()) {
			PVPUTSTR(statusMsg, "ALL CHANNELS CONNECTED");
		} state idle
	}

	/* wait in this state unless acquiring offset */
	state idle {
		
		entry {
			pvGet(validOffsetRBV);
			if (validOffsetRBV) {
				PVPUTSTR(statusMsg, "VALID OFFSET");
			}
			else {
				PVPUTSTR(statusMsg, "INVALID OFFSET");
			}
			pvGet(offsetStart);
		}
		
		when (pvConnectCount() < pvChannelCount()) {

		} state init

		when (offsetStart) {

		} state darkPrep	
	}
	/* set up records for offset frame acquisition mode */
	state darkPrep {
		
		when (arrayRate != 0.0) {
			PVPUTSTR(statusMsg, "SCAN IN PROGRESS");
			PVPUT(offsetStart, 0);
		} state idle
		
		when (arrayRate == 0.0) {
        	PVPUTSTR(statusMsg, "ACQUIRING OFFSET FRAME...");
			pvGet(numFilter);
			sprintf(tiffName, "dark_avrg%g", numFilter);
			pvPut(tiffName);
			PVPUT(trigger, 0); 
			PVPUT(processCallbacks, 1);
			PVPUT(processArrayCallbacks, 1);
			PVPUT(stats1Callbacks, 1);
			PVPUT(stats1ArrayCallbacks, 1);
			PVPUT(stats1ComputeStat, 1);
			PVPUT(filterCallbacks, 1);
			PVPUT(enableFilter, 1);
			PVPUT(autoResetFilter, 1);
			/* flat field correction has to be disabled */
			PVPUT(enableFlatField, 0);
			PVPUT(enableBackground, 0);
			PVPUT(dataType, 6);
			PVPUT(filterType, 1);  /* averaging filter */
			numImages = numFilter;
			pvPut(numImages);
			PVPUT(resetFilter, 1);
			PVPUT(imageMode, 1);
		} state darkStart
	} 
	/* start the master offset frame acquistion */
	state darkStart {
		
		entry {
%%			mytime = time(NULL);				
%%			tm1 = localtime(&mytime);
			sprintf(darkDate, "%d:%d %d/%d/%d", tm1->tm_hour, tm1->tm_min, tm1->tm_year + 1900, tm1->tm_mon + 1, tm1->tm_mday);
			pvPut(darkDate);
			PVPUT(acquire, 1)
		} 

		when (acquire == 0) {
			if (numFilter == numFilteredRBV) {
				PVPUTSTR(statusMsg, "OFFSET SAVED");
			}
			else { 
				PVPUTSTR(statusMsg, "ABORTING SEQUENCE");
			}
		} state darkFinish
	} 
	/* save offset image in area detector and enable background correction */
	state darkFinish {
		
		when (1) {
/*			printf("numFilteredRBV:%f\n", numFilteredRBV);
			printf("numFilteredRBV:%f\n", numFilteredRBV);  */
			if (numFilter == numFilteredRBV) {
				pvGet(stats1ArrayMeanRBV);
				offsetMeanRBV = stats1ArrayMeanRBV;
				pvPut(offsetMeanRBV); 
				PVPUT(saveBackground, 1);
				PVPUT(enableBackground, 1);
			}
			PVPUT(offsetStart, 0);
			PVPUT(resetFilter, 1);
			PVPUT(enableFilter, 0);
			PVPUT(imageMode, 2);
			PVPUT(numImages, 1);
			if (trigger != 1) {
				PVPUT(trigger, 1);
			}
		} state idle
	}
}