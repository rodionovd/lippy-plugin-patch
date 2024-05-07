//
//  LippyPatcher.m
//  LippyPatcher
//
//  Created by Dmitry Rodionov on 06.05.2024.
//

#import "LippyPatcher.h"
#import "Aspects.h"
#import <objc/runtime.h>

@implementation LippyPatcher

+ (void)load
{
    NSBundle *originalLippyBundle = ^NSBundle *(void) {
        NSURL *url = [[[NSBundle bundleForClass:self] builtInPlugInsURL] URLByAppendingPathComponent:@"Lippy.bundle"];
        return [NSBundle bundleWithURL:url];
    }();
    [originalLippyBundle load];
    NSCAssert(NSClassFromString(@"Lippy"), @"The original Lippy bundle was not loaded successfully");

    Class MSDocument = NSClassFromString(@"MSDocument");
    NSCAssert(MSDocument != nil, @"");
    [MSDocument aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:^(id<AspectInfo> aspectInfo, NSString *keyPath) {
        NSInvocation *invocation = aspectInfo.originalInvocation;
        // Replace the key path in [MSDocument valueForKeyPath:@"selectedLayers.layers"] to just "selectedLayers"
        if ([keyPath isEqualToString:@"selectedLayers.layers"]) {
            NSString *patchedKeyPath = @"selectedLayers";
            [invocation setArgument:&patchedKeyPath atIndex:2];
        }
        // Lippy's Sketch version number parser has a common flaw: it doesn't support 3-digit major versions,
        // which makes it believe it's running on e.g. Sketch 10.0 instead of 100, which in turn makes it
        // choose a wrong API to use in this case. We fix it back to the correct one
        if ([keyPath isEqualToString:@"currentContentViewController.contentDrawView"]) {
            NSString *patchedKeyPath = @"currentContentViewController.canvasView";
            [invocation setArgument:&patchedKeyPath atIndex:2];
        }
        [invocation invoke];
    } error:nil];

    // Fix +[Lippy colorFromHex:] to use modern Sketch API
    Class LippyParentClass = object_getClass(NSClassFromString(@"Lippy"));
    NSCAssert(LippyParentClass != nil, @"");
    SEL colorFromHexSel = NSSelectorFromString(@"colorFromHex:");
    [LippyParentClass aspect_hookSelector:colorFromHexSel withOptions:AspectPositionInstead usingBlock:^(id<AspectInfo> aspectInfo, NSString *hex) {
        Class MSColor = NSClassFromString(@"MSColor");
        id msColor = [MSColor colorWithHex:hex alpha:1.0];
        NSColor *result = [msColor NSColorWithColorSpace:[NSColorSpace deviceRGBColorSpace].CGColorSpace];
        NSInvocation *invocation = aspectInfo.originalInvocation;
        [invocation setReturnValue:&result];
    } error:nil];

    // Fix -valueForKeyPath:@"absoluteRect.origin" in various classes
    __auto_type absoluteRectFixup = ^(id<AspectInfo> aspectInfo, NSString *keyPath) {
        NSInvocation *invocation = aspectInfo.originalInvocation;
        [invocation invoke];
        if ([keyPath isEqualToString:@"absoluteRect.origin"]) {
            id parent = [aspectInfo.instance parentObject];
            NSRect frame = [[aspectInfo.instance valueForKeyPath:@"frame.rect"] rectValue];
            NSRect absoluteFrame = [parent convertRect:frame toCoordinateSpace:nil];

            NSValue *result = [NSValue valueWithPoint:absoluteFrame.origin];
            [invocation setReturnValue:&result];
        }
    };

    // MARK: - Text Layers
    Class MSTextLayer = NSClassFromString(@"MSTextLayer");
    [MSTextLayer aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:absoluteRectFixup error:nil];

    // MARK: - Symbol Instances (WIP)
    Class MSSymbolInstance = NSClassFromString(@"MSSymbolInstance");
    [MSSymbolInstance aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:absoluteRectFixup error:nil];

    // TODO: <dmitry.rodionov> fix [MSSymbolInstance valueForKeyPath:@"overrideContainer.selectedOverrides"]
        // -> an array of MSOverrideRepresentation
    // TODO: <dmitry.rodionov> fix [<text override class> valueForKeyPath:@"availableOverride.affectedLayer.rect"];
    // TODO: <dmitry.rodionov> fix [<text override class> valueForKeyPath:@"availableOverride.overrideValue"];

    // to get an override point => [activeTextOverride valueForKeyPath:@"availableOverride.overridePoint"];
}


// MARK: -
// A few no-ops to make ARC happy about these selectors from Sketch SPI that we use in this patch

+ (id)colorWithHex:(NSString *)hex alpha:(CGFloat)alpha { return nil; }
- (id)NSColorWithColorSpace:(CGColorSpaceRef)colorSpace { return nil; }
- (id)parentObject { return nil; }
- (NSRect)convertRect:(NSRect)rect toCoordinateSpace:(id)space { return NSZeroRect; }

@end
