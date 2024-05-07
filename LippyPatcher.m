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

// FIXME: <dmitry.rodionov> Lippy won't hold a strong reference to its activeTextOverride, so here we are, keeping it alive just like this
static NSArray *kSelectedTextOverrides = nil;

static NSValue *MSLayerAbsoluteRect(id /* __kindof MSLayer */ layer) {
    id parent = [layer parentObject];
    NSRect frame = [[layer valueForKeyPath:@"frame.rect"] rectValue];
    NSRect absoluteFrame = [parent convertRect:frame toCoordinateSpace:nil];
    return [NSValue valueWithPoint:absoluteFrame.origin];
};

static NSArray *MSSymbolInstanceSelectedTextOverrides(id /* MSSymbolInstance */ instance) {
    // We filter for the currently selected text overrides on the given symbol instance
    NSSet *selection = [[instance valueForKeyPath:@"documentData.currentPage.currentSelection"]
                        filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, id _Nullable bindings) {
        return [item valueForKey:@"primarySelection"] == instance && [item canOverrideTextStringValue];
    }]];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:selection.count];
    for (id item in selection) {
        // FIXME: <dmitry.rodionov> this should've been a proper object, but who cares as long as the interface is the same
        [result addObject:@{
            @"selectionID": @"stringValue",
            @"availableOverride": @{
                @"overrideValue": [item valueForKeyPath:@"selectedLayer.stringValue"] ?: @"",
                @"overridePoint": [item textStringOverridePoint],
                @"affectedLayer": @{
                    @"rect": ({
                        NSRect absoluteRect = [[item valueForKey:@"absoluteAlignmentRect"] rectValue];
                        @([instance convertRect:absoluteRect fromCoordinateSpace:nil]);
                    })
                }
            }
        }];
    }
    return result;
};

+ (void)load
{
    NSBundle *originalLippyBundle = ^NSBundle *(void) {
        NSURL *url = [[[NSBundle bundleForClass:self] builtInPlugInsURL] URLByAppendingPathComponent:@"Lippy.bundle"];
        return [NSBundle bundleWithURL:url];
    }();
    [originalLippyBundle load];
    NSCAssert(NSClassFromString(@"Lippy"), @"The original Lippy bundle was not loaded successfully");

    // Lippy 1.1.2 => build 192
    if (![[originalLippyBundle objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey] isEqualToString:@"192"]) {
        NSLog(@"[LippyPatcher] Unexpected Lippy plugin version, abort the patch");
        return;
    }

    // See kSelectedOverrides definition at the top of this file
    Class LippyMainViewController = NSClassFromString(@"LippyMainViewController");
    SEL showEditorForContextSel = NSSelectorFromString(@"showEditorForContext:");
    [LippyMainViewController aspect_hookSelector:showEditorForContextSel withOptions:AspectPositionBefore usingBlock:^() {
        kSelectedTextOverrides = nil;
    } error:nil];

    Class MSDocument = NSClassFromString(@"MSDocument");
    NSCAssert(MSDocument != nil, @"");
    [MSDocument aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:^(id<AspectInfo> aspectInfo, NSString *keyPath) {
        NSInvocation *invocation = aspectInfo.originalInvocation;
        // -[MSDocument selectedLayers] no longer contains symbol instances for which one of the overrides
        // is selected, so we use a different API (which also works for plain selection)
        if ([keyPath isEqualToString:@"selectedLayers.layers"]) {
            NSArray *primarySelection = [[aspectInfo.instance valueForKeyPath:@"documentData.currentPage.currentSelection.primarySelection"] allObjects];
            void *result = (__bridge void *)primarySelection;
            [invocation setReturnValue:&result];
            return;
        }
        // Lippy's Sketch version number parser has a common flaw: it doesn't support 3-digit major versions,
        // which makes it believe it's running on e.g. Sketch 10.0 instead of 100, which in turn makes it
        // choose a wrong API to use in this case. We fix it back to the correct one
        // TODO: <dmitry.rodionov> patch -[Lippy sketchVersion] directly to return a correct value?
        if ([keyPath isEqualToString:@"currentContentViewController.contentDrawView"]) {
            NSString *patchedKeyPath = @"currentContentViewController.canvasView";
            [invocation setArgument:&patchedKeyPath atIndex:2];
        }
        [invocation invoke];
    } error:nil];

    // Fix +[Lippy colorFromHex:] to use an up-to-date Sketch API
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

    // Fix absoluteRect calculation for MSTextLayers
    Class MSTextLayer = NSClassFromString(@"MSTextLayer");
    [MSTextLayer aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:^(id<AspectInfo> aspectInfo, NSString *keyPath) {
        NSInvocation *invocation = aspectInfo.originalInvocation;
        [invocation invoke];
        if ([keyPath isEqualToString:@"absoluteRect.origin"]) {
            NSValue *result = MSLayerAbsoluteRect(aspectInfo.instance);
            [invocation setReturnValue:&result];
        }
    } error:nil];

    Class MSSymbolInstance = NSClassFromString(@"MSSymbolInstance");
    [MSSymbolInstance aspect_hookSelector:@selector(valueForKeyPath:) withOptions:AspectPositionInstead usingBlock:^(id<AspectInfo> aspectInfo, NSString *keyPath) {
        NSInvocation *invocation = aspectInfo.originalInvocation;
        [invocation invoke];

        // Fix absoluteRect calculation for MSSymbolInstances
        if ([keyPath isEqualToString:@"absoluteRect.origin"]) {
            NSValue *result = MSLayerAbsoluteRect(aspectInfo.instance);
            [invocation setReturnValue:&result];
        }
        // Prepare an artificial array of selected overrides on the given symbol instance
        // in a format expected by Lippy's routines
        if ([keyPath isEqualToString:@"overrideContainer.selectedOverrides"]) {
            // See kSelectedOverrides definition at the top of this file
            kSelectedTextOverrides = MSSymbolInstanceSelectedTextOverrides(aspectInfo.instance);
            void *result = (__bridge void *)kSelectedTextOverrides;
            [invocation setReturnValue:&result];
        }
    } error:nil];
}


// MARK: -
// A few no-ops to make ARC happy about these selectors from Sketch SPI that we use in this patch

+ (id)colorWithHex:(NSString *)hex alpha:(CGFloat)alpha { return nil; }
- (id)NSColorWithColorSpace:(CGColorSpaceRef)colorSpace { return nil; }
- (id)parentObject { return nil; }
- (NSRect)convertRect:(NSRect)rect toCoordinateSpace:(id)space { return NSZeroRect; }
- (NSRect)convertRect:(NSRect)rect fromCoordinateSpace:(id)space { return NSZeroRect; }
- (NSSet *)primarySelection { return nil; }
- (BOOL)canOverrideTextStringValue { return NO; }
- (id)textStringOverridePoint { return nil; }

@end
