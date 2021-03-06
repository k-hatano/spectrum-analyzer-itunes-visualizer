//
// File:       iTunesPlugInMac.mm
//
// Abstract:   Visual plug-in for iTunes on MacOS
//
// Version:    2.0
//
// Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc. ( "Apple" )
//             in consideration of your agreement to the following terms, and your use,
//             installation, modification or redistribution of this Apple software
//             constitutes acceptance of these terms.  If you do not agree with these
//             terms, please do not use, install, modify or redistribute this Apple
//             software.
//
//             In consideration of your agreement to abide by the following terms, and
//             subject to these terms, Apple grants you a personal, non - exclusive
//             license, under Apple's copyrights in this original Apple software ( the
//             "Apple Software" ), to use, reproduce, modify and redistribute the Apple
//             Software, with or without modifications, in source and / or binary forms;
//             provided that if you redistribute the Apple Software in its entirety and
//             without modifications, you must retain this notice and the following text
//             and disclaimers in all such redistributions of the Apple Software. Neither
//             the name, trademarks, service marks or logos of Apple Inc. may be used to
//             endorse or promote products derived from the Apple Software without specific
//             prior written permission from Apple.  Except as expressly stated in this
//             notice, no other rights or licenses, express or implied, are granted by
//             Apple herein, including but not limited to any patent rights that may be
//             infringed by your derivative works or by other works in which the Apple
//             Software may be incorporated.
//
//             The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
//             WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
//             WARRANTIES OF NON - INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
//             PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION
//             ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
//
//             IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
//             CONSEQUENTIAL DAMAGES ( INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//             SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//             INTERRUPTION ) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION
//             AND / OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER
//             UNDER THEORY OF CONTRACT, TORT ( INCLUDING NEGLIGENCE ), STRICT LIABILITY OR
//             OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Copyright © 2001-2011 Apple Inc. All Rights Reserved.
//

//-------------------------------------------------------------------------------------------------
//	includes
//-------------------------------------------------------------------------------------------------

#import "iTunesPlugIn.h"

#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import <string.h>

//-------------------------------------------------------------------------------------------------
//	constants, etc.
//-------------------------------------------------------------------------------------------------

#define kTVisualPluginName              CFSTR("Spectrum Analyzer Visualizer")

//-------------------------------------------------------------------------------------------------
//	exported function prototypes
//-------------------------------------------------------------------------------------------------

extern "C" OSStatus iTunesPluginMainMachO( OSType inMessage, PluginMessageInfo *inMessageInfoPtr, void *refCon ) __attribute__((visibility("default")));

#if USE_SUBVIEW
//-------------------------------------------------------------------------------------------------
//	VisualView
//-------------------------------------------------------------------------------------------------

@interface VisualView : NSView
{
	VisualPluginData *	_visualPluginData;
}

@property (nonatomic, assign) VisualPluginData * visualPluginData;

-(void)drawRect:(NSRect)dirtyRect;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
-(void)keyDown:(NSEvent *)theEvent;

@end

#endif	// USE_SUBVIEW

#define SPECTRUMS_NUM 32

long maxSpectrum[SPECTRUMS_NUM] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double timeOfMaxSpectrum[SPECTRUMS_NUM] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
double fadeoutTime;

UInt8 averageOfSpectrumData(VisualPluginData *visualPluginData, UInt8 *spectrumData, NSInteger position, NSInteger length){
    unsigned long result = 0;
    NSInteger index;
    if (visualPluginData->playing) {
        for (index = position; index < position + length; index++) {
            result += spectrumData[index];
        }
        return (UInt8)(result / length);
    } else {
        return 0;
    }
}

//-------------------------------------------------------------------------------------------------
//	DrawVisual
//-------------------------------------------------------------------------------------------------
//
void DrawVisual( VisualPluginData * visualPluginData )
{
	CGRect			drawRect;
	CGPoint			where;

	if ( visualPluginData->destView == NULL )
		return;

	CGRect viewRect = [visualPluginData->destView bounds];
    drawRect = viewRect;
    
	[[NSColor blackColor] set];
	NSRectFill( drawRect );
    
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor grayColor]
                                                         endingColor:[NSColor blackColor]];
    drawRect.size.height /= 2;
    [gradient drawInRect:drawRect angle:90.0f];
    
    NSInteger samplesInAll = sizeof(visualPluginData->renderData.spectrumData[0]) / sizeof(visualPluginData->renderData.spectrumData[0][0]) / 2;
    NSInteger samplesInBar = samplesInAll / SPECTRUMS_NUM;
    
    NSInteger widthUnit = [visualPluginData->destView bounds].size.width / (SPECTRUMS_NUM + 4);
    NSInteger heightUnit = [visualPluginData->destView bounds].size.height;
    
    NSInteger x,y,width,height;
    
    for (NSInteger i = 0; i < SPECTRUMS_NUM; i++) {
        [[NSColor colorWithHue:i/(SPECTRUMS_NUM * 1.25f) saturation:1.0f brightness:1.0f alpha:1.0f] set];
        
        UInt8 spectrum = averageOfSpectrumData(visualPluginData, visualPluginData->renderData.spectrumData[0], i * samplesInBar, samplesInBar);
        
        if (spectrum > maxSpectrum[i]) {
            maxSpectrum[i] = spectrum;
            timeOfMaxSpectrum[i] = CFAbsoluteTimeGetCurrent();
        } else if (CFAbsoluteTimeGetCurrent() > timeOfMaxSpectrum[i]) {
            if (maxSpectrum[i] > 0 ){
                maxSpectrum[i] -= 2;
            }
        }
        
        // Positive Bar
        x = widthUnit * (i + 2) + (widthUnit / SPECTRUMS_NUM);
        width = widthUnit - (widthUnit / (SPECTRUMS_NUM / 2));
        y = heightUnit / 6;
        height = spectrum / 256.0f * (heightUnit * 2 / 3);
        
        drawRect = NSMakeRect( x, y, width, height );
        NSRectFill( drawRect );
        
        // Top of Positive Bar
        x = widthUnit * (i + 2) + (widthUnit / SPECTRUMS_NUM);
        width = widthUnit - (widthUnit / (SPECTRUMS_NUM / 2));
        y = heightUnit / 6 + (maxSpectrum[i] / 256.0f * (heightUnit * 2 / 3));
        height = maxSpectrum[i] <= 2 ? maxSpectrum[i] : 2;
        
        drawRect = NSMakeRect( x, y, width, height );
        NSRectFill( drawRect );
        
        // Negative (Reflected) Bar
        
        [[NSColor colorWithHue:i/(SPECTRUMS_NUM * 1.25f) saturation:1.0f brightness:1.0f alpha:0.3f] set];
        x = widthUnit * (i + 2) + (widthUnit / SPECTRUMS_NUM);
        width = widthUnit - (widthUnit / (SPECTRUMS_NUM / 2));
        y = heightUnit / 6 - (spectrum / 256.0f * (heightUnit * 2 / 3));
        height = spectrum / 256.0f * (heightUnit * 2 / 3);
        
        drawRect = NSMakeRect( x, y, width, height );
        NSRectFillUsingOperation(drawRect, NSCompositingOperationSourceOver);
    }

	// should we draw the info/artwork in the bottom-left corner?
	time_t		theTime = time( NULL );

	if ( theTime < visualPluginData->drawInfoTimeOut + 1 ){
        float width = 0;
        float height = 0;
        if (visualPluginData->currentArtwork != NULL) {
            width = visualPluginData->currentArtwork.size.width / 2;
            height = visualPluginData->currentArtwork.size.height / 2;
        }
        
        NSString *theString = NULL;
        
        NSColor *color;
        float fraction;
        if (theTime < visualPluginData->drawInfoTimeOut) {
            fadeoutTime = CFAbsoluteTimeGetCurrent();
            color = [NSColor colorWithCalibratedWhite:1.0f alpha:1.0];
            fraction = 0.75;
        } else {
            color = [NSColor colorWithCalibratedWhite:1.0f alpha:(1.0 - (CFAbsoluteTimeGetCurrent() - fadeoutTime))];
            fraction = (1.0 - (CFAbsoluteTimeGetCurrent() - fadeoutTime)) * 0.75;
        }
        
        if (fraction > 1.0) {
            fraction = 1.0;
        } else if (fraction < 0.0) {
            fraction = 0.0;
        }
        
        
        if ( visualPluginData->streamInfo.streamTitle[0] != 0 ) {
            theString = [NSString stringWithCharacters:&visualPluginData->streamInfo.streamTitle[1] length:visualPluginData->streamInfo.streamTitle[0]];
        }
        else if ( visualPluginData->trackInfo.name[0] != 0 ) {
            theString = [NSString stringWithCharacters:&visualPluginData->trackInfo.name[1] length:visualPluginData->trackInfo.name[0]];
        }
        if ( theString != NULL ){
            NSDictionary * attrs = [NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName, NULL];
            where = CGPointMake( 20 + width
                                , viewRect.size.height - 10 - 16);
            [theString drawAtPoint:where withAttributes:attrs];
        }

		theString = NULL;
        if ( visualPluginData->trackInfo.artist[0] != 0 ) {
            theString = [NSString stringWithCharacters:&visualPluginData->trackInfo.artist[1] length:visualPluginData->trackInfo.artist[0]];
        }
        if ( theString != NULL ){
            NSDictionary * attrs = [NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName, NULL];
            where = CGPointMake( 20 + width
                                , viewRect.size.height - 10 - 32);
            [theString drawAtPoint:where withAttributes:attrs];
        }
        
        
        theString = NULL;
        if ( visualPluginData->trackInfo.album[0] != 0 ) {
            theString = [NSString stringWithCharacters:&visualPluginData->trackInfo.album[1] length:visualPluginData->trackInfo.album[0]];
        }
        if ( theString != NULL ){
            NSDictionary * attrs = [NSDictionary dictionaryWithObjectsAndKeys:color, NSForegroundColorAttributeName, NULL];
            where = CGPointMake( 20 + width
                                , viewRect.size.height - 10 - 48);
            [theString drawAtPoint:where withAttributes:attrs];
        }
        
        
		if ( visualPluginData->currentArtwork != NULL &&
            (visualPluginData->streamInfo.streamTitle[0] != 0 || visualPluginData->trackInfo.name[0] != 0) )
		{
            [visualPluginData->currentArtwork drawInRect:NSMakeRect(10, viewRect.size.height - 10 - height, width, height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:fraction];
		}
	}
}

//-------------------------------------------------------------------------------------------------
//	UpdateArtwork
//-------------------------------------------------------------------------------------------------
//
void UpdateArtwork( VisualPluginData * visualPluginData, CFDataRef coverArt, UInt32 coverArtSize, UInt32 coverArtFormat )
{
	// release current image
	[visualPluginData->currentArtwork release];
	visualPluginData->currentArtwork = NULL;
	
	// create 100x100 NSImage* out of incoming CFDataRef if non-null (null indicates there is no artwork for the current track)
	if ( coverArt != NULL )
	{
		visualPluginData->currentArtwork = [[NSImage alloc] initWithData:(NSData *)coverArt];
		
		[visualPluginData->currentArtwork setSize:CGSizeMake( 100, 100 )];
	}
	
	UpdateInfoTimeOut( visualPluginData );
}

//-------------------------------------------------------------------------------------------------
//	InvalidateVisual
//-------------------------------------------------------------------------------------------------
//
void InvalidateVisual( VisualPluginData * visualPluginData )
{
	(void) visualPluginData;

#if USE_SUBVIEW
	// when using a custom subview, we invalidate it so we get our own draw calls
	[visualPluginData->subview setNeedsDisplay:YES];
#endif
}

//-------------------------------------------------------------------------------------------------
//	CreateVisualContext
//-------------------------------------------------------------------------------------------------
//
OSStatus ActivateVisual( VisualPluginData * visualPluginData, VISUAL_PLATFORM_VIEW destView, OptionBits options )
{
	OSStatus			status = noErr;

	visualPluginData->destView			= destView;
	visualPluginData->destRect			= [destView bounds];
	visualPluginData->destOptions		= options;

	UpdateInfoTimeOut( visualPluginData );

#if USE_SUBVIEW

	// NSView-based subview
	visualPluginData->subview = [[VisualView alloc] initWithFrame:visualPluginData->destRect];
	if ( visualPluginData->subview != NULL )
	{
		[visualPluginData->subview setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

		[visualPluginData->subview setVisualPluginData:visualPluginData];

		[destView addSubview:visualPluginData->subview];
	}
	else
	{
		status = memFullErr;
	}

#endif

	return status;
}

//-------------------------------------------------------------------------------------------------
//	MoveVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus MoveVisual( VisualPluginData * visualPluginData, OptionBits newOptions )
{
	visualPluginData->destRect	  = [visualPluginData->destView bounds];
	visualPluginData->destOptions = newOptions;

	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	DeactivateVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus DeactivateVisual( VisualPluginData * visualPluginData )
{
#if USE_SUBVIEW
	[visualPluginData->subview removeFromSuperview];
	[visualPluginData->subview autorelease];
	visualPluginData->subview = NULL;
	[visualPluginData->currentArtwork release];
	visualPluginData->currentArtwork = NULL;
#endif

	visualPluginData->destView			= NULL;
	visualPluginData->destRect			= CGRectNull;
	visualPluginData->drawInfoTimeOut	= 0;
	
	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	ResizeVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus ResizeVisual( VisualPluginData * visualPluginData )
{
	visualPluginData->destRect = [visualPluginData->destView bounds];

	// note: the subview is automatically resized by iTunes so nothing to do here

	return noErr;
}

//-------------------------------------------------------------------------------------------------
//	ConfigureVisual
//-------------------------------------------------------------------------------------------------
//
OSStatus ConfigureVisual( VisualPluginData * visualPluginData )
{
	(void) visualPluginData;

	// load nib
	// show modal dialog
	// update settings
	// invalidate

	return noErr;
}

#pragma mark -

#if USE_SUBVIEW

@implementation VisualView

@synthesize visualPluginData = _visualPluginData;

//-------------------------------------------------------------------------------------------------
//	isOpaque
//-------------------------------------------------------------------------------------------------
//
- (BOOL)isOpaque
{
	// your custom views should always be opaque or iTunes will waste CPU time drawing behind you
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	drawRect
//-------------------------------------------------------------------------------------------------
//
-(void)drawRect:(NSRect)dirtyRect
{
	if ( _visualPluginData != NULL )
	{
		DrawVisual( _visualPluginData );
	}
}

//-------------------------------------------------------------------------------------------------
//	acceptsFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)acceptsFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	becomeFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)becomeFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	resignFirstResponder
//-------------------------------------------------------------------------------------------------
//
- (BOOL)resignFirstResponder
{
	return YES;
}

//-------------------------------------------------------------------------------------------------
//	keyDown
//-------------------------------------------------------------------------------------------------
//
-(void)keyDown:(NSEvent *)theEvent
{
	// Handle key events here.
	// Do not eat the space bar, ESC key, TAB key, or the arrow keys: iTunes reserves those keys.

	// if the 'i' key is pressed, reset the info timeout so that we draw it again
	if ( [[theEvent charactersIgnoringModifiers] isEqualTo:@"i"] )
	{
		UpdateInfoTimeOut( _visualPluginData );
		return;
	}

	// Pass all unhandled events up to super so that iTunes can handle them.
	[super keyDown:theEvent];
}

@end

#endif	// USE_SUBVIEW

#pragma mark -

//-------------------------------------------------------------------------------------------------
//	GetVisualName
//-------------------------------------------------------------------------------------------------
//
void GetVisualName( ITUniStr255 name )
{
	CFIndex length = CFStringGetLength( kTVisualPluginName );

	name[0] = (UniChar)length;
	CFStringGetCharacters( kTVisualPluginName, CFRangeMake( 0, length ), &name[1] );
}

//-------------------------------------------------------------------------------------------------
//	GetVisualOptions
//-------------------------------------------------------------------------------------------------
//
OptionBits GetVisualOptions( void )
{
	OptionBits		options = (kVisualSupportsMuxedGraphics | kVisualWantsIdleMessages);
	
#if USE_SUBVIEW
	options |= kVisualUsesSubview;
#endif

	return options;
}

//-------------------------------------------------------------------------------------------------
//	iTunesPluginMainMachO
//-------------------------------------------------------------------------------------------------
//
OSStatus iTunesPluginMainMachO( OSType message, PluginMessageInfo * messageInfo, void * refCon )
{
	OSStatus		status;
	
	(void) refCon;
	
	switch ( message )
	{
		case kPluginInitMessage:
			status = RegisterVisualPlugin( messageInfo );
			break;
			
		case kPluginCleanupMessage:
			status = noErr;
			break;
			
		default:
			status = unimpErr;
			break;
	}
	
	return status;
}
