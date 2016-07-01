	ComponentComment ("Based on SoftVDigXDispatch.h from SoftVDigX")

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
		
		ComponentCall	(GetMaskPixMap)				// not used for Compressed Source ignore
		ComponentError	(0x0007)
		ComponentCall	(GetPlayThruDestination)	// not used for Compressed Source ignore
		ComponentCall	(UseThisCLUT)				// not used for Compressed Source ignore
		ComponentCall	(SetInputGammaValue)		// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetInputGammaValue)		// not called directly by Sequence Grabber QT6.3
		
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
		
		ComponentCall	(GrabOneFrame)				// not used for Compressed Source ignore
		ComponentCall	(GetMaxAuxBuffer)			// not used for Compressed Source ignore
		ComponentError	(0x0018)					// private
					
			ComponentCall	(GetDigitizerInfo)
			ComponentCall	(GetCurrentFlags)
		
		ComponentCall	(SetKeyColor)				// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetKeyColor)				// not called unless vdTypeKey
		ComponentCall	(AddKeyColor)				// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetNextKeyColor)			// not called directly by Sequence Grabber QT6.3
		ComponentCall	(SetKeyColorRange)			// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetKeyColorRange)			// not called directly by Sequence Grabber QT6.3
		ComponentCall	(SetDigitizerUserInterrupt)	// not used
		ComponentCall	(SetInputColorSpaceMode)	// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetInputColorSpaceMode)	// not called directly by Sequence Grabber QT6.3
		ComponentCall	(SetClipState)
		ComponentCall	(GetClipState)
		ComponentCall	(SetClipRgn)
		ComponentCall	(ClearClipRgn)
		ComponentCall	(GetCLUTInUse)				// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(SetPLLFilterType)		// called by Video Source Panel if implemented
			ComponentCall	(GetPLLFilterType)		// called by Video Source Panel if implemented
			
		ComponentCall	(GetMaskandValue)			// not called unless vdTypeAlpha
		ComponentCall	(SetMasterBlendLevel)		// not called directly by Sequence Grabber QT6.3
		ComponentCall	(SetPlayThruDestination)	// not used for Compressed Source ignore
		ComponentCall	(SetPlayThruOnOff)			// not used for Compressed Source ignore
		ComponentCall	(SetFieldPreference)		// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetFieldPreference)		// not called directly by Sequence Grabber QT6.3
		ComponentError	(0x0031)					// private
		ComponentCall	(PreflightDestination)		// not used for Compressed Source ignore
		ComponentCall	(PreflightGlobalRect)		// not used for Compressed Source ignore
		ComponentCall	(SetPlayThruGlobalRect)		// not used for Compressed Source ignore
		ComponentCall	(SetInputGammaRecord)		// not called directly by Sequence Grabber QT6.3
		ComponentCall	(GetInputGammaRecord)		// not called directly by Sequence Grabber QT6.3
		
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
		
		ComponentCall	(SetupBuffers)				// not used for Compressed Source ignore
		ComponentCall	(GrabOneFrameAsync)			// not used for Compressed Source ignore
		ComponentCall	(Done)						// not used for Compressed Source ignore
		
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
		
		ComponentCall	(GetSoundInputDriver)
		ComponentCall	(GetDMADepths)					// not used for Compressed Source ignore
				
			ComponentCall	(GetPreferredTimeScale)
		
		ComponentCall	(ReleaseAsyncBuffers)			// not used for Compressed Source ignore
		ComponentError	(0x0053)
		
			ComponentCall	(SetDataRate)
			ComponentCall	(GetTimeCode)
			
		ComponentCall	(UseSafeBuffers)				// not used for Compressed Source ignore
		ComponentCall	(GetSoundInputSource)
		
			ComponentCall	(GetCompressionTime)
		
		ComponentCall	(SetPreferredPacketSize)
		ComponentCall	(SetPreferredImageDimensions)	// not called directly by Sequence Grabber QT6.3
		
			ComponentCall	(GetPreferredImageDimensions)
			ComponentCall	(GetInputName)
		
		ComponentCall	(SetDestinationPort)			// not used for Compressed Source ignore
		
			ComponentCall	(GetDeviceNameAndFlags)
			ComponentCall	(CaptureStateChanging)
			ComponentCall	(GetUniqueIDs)
			ComponentCall	(SelectUniqueIDs)
	ComponentRangeEnd (1)
