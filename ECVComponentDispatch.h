	ComponentComment ("SoftVDigXDispatch.h for SoftVDigX")

	ComponentSelectorOffset (4)

	ComponentRangeCount (1)
	ComponentRangeShift (8)
	ComponentRangeMask	(FF)

	ComponentStorageType (Ptr)

ComponentComment("Standard Component Range")

	ComponentRangeBegin (0)
		StdComponentCall	(Version)
		StdComponentCall	(CanDo)
		StdComponentCall	(Close)
		StdComponentCall	(Open)
	ComponentRangeEnd (0)
	
ComponentComment("Video Digitizer Component Range")

	ComponentRangeBegin (1)
		ComponentError	(0)
		
			ComponentCall	(GetMaxSrcRect)
			ComponentCall	(GetActiveSrcRect)
			ComponentCall	(SetDigitizerRect)
			ComponentCall	(GetDigitizerRect)
			ComponentCall	(GetVBlankRect)
		
		ComponentError	(GetMaskPixMap)				// not used for Compressed Source ignore
		ComponentError	(0x0007)
		ComponentError	(GetPlayThruDestination)	// not used for Compressed Source ignore
		ComponentError	(UseThisCLUT)				// not used for Compressed Source ignore
		ComponentError	(SetInputGammaValue)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetInputGammaValue)		// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(SetBrightness)
			ComponentCall	(GetBrightness)
			ComponentCall	(SetContrast)
			ComponentCall	(SetHue)
			ComponentCall	(SetSharpness)
			ComponentCall	(SetSaturation)
			ComponentCall	(GetContrast)
			ComponentCall	(GetHue)
			ComponentCall	(GetSharpness)
			ComponentCall	(GetSaturation)
		
		ComponentError	(GrabOneFrame)				// not used for Compressed Source ignore
		ComponentError	(GetMaxAuxBuffer)			// not used for Compressed Source ignore
		ComponentError	(0x0018)					// private
					
			ComponentCall	(GetDigitizerInfo)
			ComponentCall	(GetCurrentFlags)
		
		ComponentError	(SetKeyColor)				// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetKeyColor)				// not called unless vdTypeKey
		ComponentError	(AddKeyColor)				// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetNextKeyColor)			// not called directly by Sequence Grabber QT6.3
		ComponentError	(SetKeyColorRange)			// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetKeyColorRange)			// not called directly by Sequence Grabber QT6.3
		ComponentError	(SetDigitizerUserInterrupt)	// not used
		ComponentError	(SetInputColorSpaceMode)	// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetInputColorSpaceMode)	// not called directly by Sequence Grabber QT6.3
		ComponentError	(SetClipState)
		ComponentError	(GetClipState)
		ComponentError	(SetClipRgn)
		ComponentError	(ClearClipRgn)
		ComponentError	(GetCLUTInUse)				// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(SetPLLFilterType)		// called by Video Source Panel if implemented
			ComponentCall	(GetPLLFilterType)		// called by Video Source Panel if implemented
			
		ComponentError	(GetMaskandValue)			// not called unless vdTypeAlpha
		ComponentError	(SetMasterBlendLevel)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(SetPlayThruDestination)	// not used for Compressed Source ignore
		ComponentError	(SetPlayThruOnOff)			// not used for Compressed Source ignore
		ComponentError	(SetFieldPreference)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetFieldPreference)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(0x0031)					// private
		ComponentError	(PreflightDestination)		// not used for Compressed Source ignore
		ComponentError	(PreflightGlobalRect)		// not used for Compressed Source ignore
		ComponentError	(SetPlayThruGlobalRect)		// not used for Compressed Source ignore
		ComponentError	(SetInputGammaRecord)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(GetInputGammaRecord)		// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(SetBlackLevelValue)
			ComponentCall	(GetBlackLevelValue)
			ComponentCall	(SetWhiteLevelValue)
			ComponentCall	(GetWhiteLevelValue)
			ComponentCall	(GetVideoDefaults)
			ComponentCall	(GetNumberOfInputs)
			ComponentCall	(GetInputFormat)
			ComponentCall	(SetInput)
			ComponentCall	(GetInput)
			ComponentCall	(SetInputStandard)
		
		ComponentError	(SetupBuffers)				// not used for Compressed Source ignore
		ComponentError	(GrabOneFrameAsync)			// not used for Compressed Source ignore
		ComponentError	(Done)						// not used for Compressed Source ignore
		
			// these are required selectors for Compress Source
			// other Grab and PlayThru related selectors are no longer
			// applicable on MacOS X and should be ignored
			ComponentCall	(SetCompression)
			ComponentCall	(CompressOneFrameAsync)
			ComponentCall	(CompressDone)
			ComponentCall	(ReleaseCompressBuffer)
			ComponentCall	(GetImageDescription)
			ComponentCall	(ResetCompressSequence)
			ComponentCall	(SetCompressionOnOff)
			ComponentCall	(GetCompressionTypes)
			ComponentCall	(SetTimeBase)
			ComponentCall	(SetFrameRate)
			ComponentCall	(GetDataRate)
		
		ComponentError	(GetSoundInputDriver)
		ComponentError	(GetDMADepths)					// not used for Compressed Source ignore
				
			ComponentCall	(GetPreferredTimeScale)
		
		ComponentError	(ReleaseAsyncBuffers)			// not used for Compressed Source ignore
		ComponentError	(0x0053)
		
			ComponentCall	(SetDataRate)
			ComponentCall	(GetTimeCode)
			
		ComponentError	(UseSafeBuffers)				// not used for Compressed Source ignore
		ComponentError	(GetSoundInputSource)
		
			ComponentCall	(GetCompressionTime)
		
		ComponentError	(SetPreferredPacketSize)
		ComponentError	(SetPreferredImageDimensions)	// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(GetPreferredImageDimensions)
			ComponentCall	(GetInputName)
		
		ComponentError	(SetDestinationPort)			// not used for Compressed Source ignore
		
			ComponentCall	(GetDeviceNameAndFlags)
			ComponentCall	(CaptureStateChanging)
			ComponentCall	(GetUniqueIDs)
			ComponentCall	(SelectUniqueIDs)
	ComponentRangeEnd (1)