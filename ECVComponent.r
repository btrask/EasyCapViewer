#define thng_RezTemplateVersion 1

#include <Carbon/Carbon.r>
#include <QuickTime/QuickTime.r>

resource 'thng' (256)
{
	'vdig', // Type
	'soft', // SubType
	'asdf', // Manufacturer
	0, // use componentHasMultiplePlatforms
	0,
	0,
	0,
	'STR ', // Name Type
	128, // Name ID
	'STR ', // Info Type
	129, // Info ID
	0, // Icon Type
	0, // Icon ID
	0, // Version
	componentHasMultiplePlatforms + componentDoAutoVersion, // Registration flags
	0, // Resource ID of Icon Family
	{
		0,
		'dlle', // Entry point found by symbol name 'dlle' resource
		256, // ID of 'dlle' resource
#if defined(ppc_YES)
		platformPowerPCNativeEntryPoint,
#elif defined(i386_YES)
		platformIA32NativeEntryPoint,
#endif
	};
};
resource 'STR ' (128)
{
	"ECVComponent"
};
resource 'STR ' (129)
{
	"EasyCapViewer QuickTime Video Digitizer Component"
};
resource 'dlle' (256)
{
	"ECVComponentDispatch"
};
