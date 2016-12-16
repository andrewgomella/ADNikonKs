program makeFlat ( "A=SIM:Qi2, X=SIM:XRAY" )
#define MAKE_FLAT_VERSION 1.0
/**************************************************************************************************
 *	Program to start master flat frame acquisition sequence for DS-Qi2. Meant to work with oxford
 *  x-ray for now.
 *
 *	by Alireza Panna, NIH/NHLBI/IPL
 *	26 February, 2016
 *
 *	#  A    	= prefix for all the PV's associatd with the camera ioc.
 *	#  X    	= prefix for all the PV's associatd with the xray ioc.
 *  
 *  __log__ 	= 02/26/2016: (AP) Version 1.0 created
 *				= 12/16/2016: (AP) Remove tsDefs.h include
 *
 *	__to-do__  	= 			  	
 ****************************************************************************************************/ 

/*===========================Option statements========================*/
option +r; /* allows running more than one copy with different macros */
option -c; /* don't wait for channel connections*/
option -l; /* use C line numbers in error messages etc. */
option +d; /* Turn on run time debug messages */
option +w; /* Suppress snc compiler warnings */
option -s; /* dont run in safe mode */

#include "seqPVmacros.h"
/* Escape to C code for C includes using %% */
%% #include <string.h>
%% #include <epicsThread.h>
%% #include <epicsTime.h>

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
PV (short,  	flatStart,  			"{A}:START_FLAT",					EvFlag);		/* start flat sequence */
PV (string, 	statusMsg,  	   		"{A}:FLAT_STATUS",					NoMon);			/* for status message string */
PV (string, 	flatDate,  	   			"{A}:FLAT_DATE",					NoMon);			/* for flat field date tag */
PV (double, 	flatMeanRBV,  	   		"{A}:FLAT_MEAN_RBV",				NoMon);			/* master flat frame mean counts */
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
PV (short,  	enableFlatField,		"{A}:Proc1:EnableFlatField", 		NoMon);			/* Enable flat field  correction */
PV (short,  	enableBackground,		"{A}:Proc1:EnableBackground", 		NoMon);			/* Enable background correction */
PV (short,  	saveFlatField,			"{A}:Proc1:SaveFlatField", 			NoMon);			/* Save flat field correction */
PV (double, 	scaleFlat,   			"{A}:Proc1:ScaleFlatField", 		NoMon);			/* Scaling factor for flat field */
PV (short,  	validFlatRBV,  			"{A}:Proc1:ValidFlatField_RBV",	    EvFlag);		/* check if flat field is valid */
PV (short,  	trigger,    			"{A}:cam1:NikonTriggerMode", 		Monitor);		/* set the trigger 0 for live, 1 for hard */
PV (short,  	acquire,    			"{A}:cam1:Acquire", 				Monitor);		/* acquire image set */
PV (double, 	numImages,   			"{A}:cam1:NumImages", 				NoMon);			/* How many images to acquire */
PV (double, 	numImagesRBV,   		"{A}:cam1:NumImagesCounter_RBV",	NoMon);
PV (double, 	imageMode,   			"{A}:cam1:ImageMode", 				NoMon);			/* qi2 image mode=>single, multiple, continous */
PV (double, 	acquireTime,   			"{A}:cam1:AcquireTime", 			NoMon);
PV (double,  	arrayRate,				"{A}:image1:ArrayRate_RBV", 		Monitor);		/* array rate */

PV (short,		xray_status_rbv,		"{X}:STATUS_RBV", 					Monitor);	/* xray status monitor */
PV (double,		xray_watt_rbv,			"{X}:WATT_RBV", 					Monitor);	/* xray flux readback (W) */
PV (double,		xray_watt,				"{X}:WATT_MIN", 					NoMon);		/* xray flux (W) */
PV (short,		xray_enable,			"{X}:ON", 							NoMon);		/* xray on/off */

char   tiffName[256];
assign tiffName to "{A}:TIFF1:FileName";

%% long mytime;
%% string tempName;
%% struct tm *tm1;

/*====================State Sets====================*/
ss makeFlat
{
	state init {
		
		when (pvConnectCount() < pvChannelCount()) {
			PVPUTSTR(statusMsg, "OFFLINE");
		} state init
		
		when (pvConnectCount() == pvChannelCount()) {
			PVPUTSTR(statusMsg, "ALL CHANNELS CONNECTED");
		} state idle
	}

	/* wait in this state unless acquiring flat field */
	state idle {
		
		entry {
			pvGet(validFlatRBV);

			if (validFlatRBV) {
				PVPUTSTR(statusMsg, "VALID FLAT FIELD");
			}
			else {
				PVPUTSTR(statusMsg, "INVALID FLAT FIELD");
			}
			pvGet(flatStart);
		}
		
		when (pvConnectCount() < pvChannelCount()) {

		} state init

		when (flatStart) {

		} state flatPrep	
	}
	/* set up records for master flat frame acquisition mode */
	state flatPrep {
		
		when (arrayRate != 0.0) {
			PVPUTSTR(statusMsg, "SCAN IN PROGRESS");
			PVPUT(flatStart, 0);
		} state idle
		
		when (arrayRate == 0.0) {
			pvGet(numFilter);
			sprintf(tiffName, "flat_avrg%g", numFilter);
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
			PVPUT(enableFlatField, 0);
			PVPUT(dataType, 6);
			PVPUT(filterType, 1);  /* averaging filter */
			numImages = numFilter;
			pvPut(numImages);
			PVPUT(resetFilter, 1);
			PVPUT(imageMode, 1);
			pvGet(xray_watt);

		} state xrayOn
	} 
	
	state xrayOn {
		entry {
			PVPUT(xray_enable, 1);
		}
		when (xray_status_rbv == 2 && xray_watt_rbv + 3 >= xray_watt) {
			PVPUTSTR(statusMsg, "ACQUIRING FLAT FRAME...");
		} state flatStart

		when (xray_status_rbv == 0) {
			PVPUTSTR(statusMsg, "XRAY IS WARMING UP");
		} state flatFinish
	}
	/* start the master flatframe acquistion */
	state flatStart {
		entry {
%%			mytime = time(NULL);				
%%			tm1 = localtime(&mytime);
			sprintf(flatDate, "%.2d/%.2d/%.2d %.2d:%.2d", tm1->tm_year + 1900, tm1->tm_mon + 1, tm1->tm_mday, tm1->tm_hour, tm1->tm_min);
			pvPut(flatDate);
			PVPUT(acquire, 1)
		} 

		when (acquire == 0) {
			if (numFilter == numFilteredRBV) {
				PVPUTSTR(statusMsg, "FLAT FIELD SAVED");
			}
			else { 
				PVPUTSTR(statusMsg, "ABORTING SEQUENCE");
			}
		} state flatFinish
	} 
	/* save FLAT image in area detector and enable background correction */
	state flatFinish {
		
		when (1) {
			if (numFilter == numFilteredRBV) {
				pvGet(stats1ArrayMeanRBV);
				flatMeanRBV = stats1ArrayMeanRBV;
				pvPut(flatMeanRBV); 
				PVPUT(saveFlatField, 1);
				PVPUT(enableFlatField, 1);
			}
			PVPUT(enableBackground, 1);
			PVPUT(xray_enable, 0);
			PVPUT(flatStart, 0);
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