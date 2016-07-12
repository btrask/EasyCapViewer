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
#if defined(ppc_YES)
		0, // Component Flags
		'dlle', // Code Resource type - Entry point found by symbol name 'dlle' resource
		256, // ID of 'dlle' resource
		platformPowerPCNativeEntryPoint,
#endif
#if defined(i386_YES)
		0, // Component Flags
		'dlle', // Code Resource type - Entry point found by symbol name 'dlle' resource
		256, // ID of 'dlle' resource
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
