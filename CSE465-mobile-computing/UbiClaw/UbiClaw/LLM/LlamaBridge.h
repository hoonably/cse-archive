#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ bridge to llama.cpp C API.
/// Owns llama_model* and llama_context*; provides in-process inference
/// with runtime thread count control.
@interface LlamaBridge : NSObject

/// Whether a model is currently loaded.
@property (nonatomic, readonly) BOOL isModelLoaded;

/// Load a GGUF model from disk. Returns YES on success.
/// Must be called before startGeneration.
- (BOOL)loadModelAtPath:(NSString *)modelPath
               nThreads:(int)nThreads
                  nCtx:(int)nCtx;

/// Begin generation on a background queue. Tokens stream via the callback.
/// The callback is invoked on an arbitrary thread; callers must dispatch to main if needed.
- (void)startGenerationWithPrompt:(NSString *)prompt
                   tokenCallback:(void (^)(NSString *token))callback
                      completion:(void (^)(void))completion;

/// Request cancellation of in-progress generation.
- (void)stopGeneration;

/// Set the delay in microseconds between token decode steps. Takes effect immediately.
- (void)setDecodeDelayMicroseconds:(int)us;

/// Set the QoS mode for in-process generation. Takes effect at generation start
/// and is re-applied between token decode steps.
- (void)setGenerationQoSMode:(NSInteger)mode;

/// Pause or resume token generation without unloading the model.
- (void)setGenerationPaused:(BOOL)paused;

/// Free model and context. Called automatically on dealloc but can be called early.
- (void)unloadModel;

@end

NS_ASSUME_NONNULL_END
