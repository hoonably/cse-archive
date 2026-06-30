#import "LlamaBridge.h"
#include "llama.h"
#include <atomic>
#include <pthread/qos.h>
#include <vector>
#include <string>

namespace {
enum LlamaBridgeQoSMode : NSInteger {
    LlamaBridgeQoSModeUserInitiated = 0,
    LlamaBridgeQoSModeUtility = 1,
    LlamaBridgeQoSModeBackground = 2,
};

static struct llama_sampler *CreateDeterministicSampler() {
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler *sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    return sampler;
}

static qos_class_t QoSClassForMode(NSInteger mode) {
    switch (mode) {
        case LlamaBridgeQoSModeUtility:
            return QOS_CLASS_UTILITY;
        case LlamaBridgeQoSModeBackground:
            return QOS_CLASS_BACKGROUND;
        case LlamaBridgeQoSModeUserInitiated:
        default:
            return QOS_CLASS_USER_INITIATED;
    }
}

static const char *QoSNameForMode(NSInteger mode) {
    switch (mode) {
        case LlamaBridgeQoSModeUtility:
            return "utility";
        case LlamaBridgeQoSModeBackground:
            return "background";
        case LlamaBridgeQoSModeUserInitiated:
        default:
            return "user_initiated";
    }
}
}

@implementation LlamaBridge {
    struct llama_model   *_model;
    struct llama_context *_ctx;
    struct llama_sampler *_sampler;
    const struct llama_vocab *_vocab;
    std::atomic<bool>     _cancelRequested;
    std::atomic<bool>     _generating;
    std::atomic<int>      _decodeDelayUs;
    std::atomic<bool>     _paused;
    std::atomic<NSInteger> _generationQoSMode;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = nullptr;
        _ctx = nullptr;
        _sampler = nullptr;
        _vocab = nullptr;
        _cancelRequested.store(false);
        _generating.store(false);
        _decodeDelayUs.store(0);
        _paused.store(false);
        _generationQoSMode.store(LlamaBridgeQoSModeUserInitiated);
    }
    return self;
}

- (void)dealloc {
    [self unloadModel];
}

- (BOOL)isModelLoaded {
    return _model != nullptr && _ctx != nullptr;
}

// MARK: - Model loading

- (BOOL)loadModelAtPath:(NSString *)modelPath
               nThreads:(int)nThreads
                  nCtx:(int)nCtx {
    [self unloadModel];

    llama_backend_init();

    // Load model
    struct llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = 99;
    _model = llama_model_load_from_file([modelPath UTF8String], modelParams);
    if (!_model) {
        NSLog(@"LlamaBridge: failed to load model at %@", modelPath);
        return NO;
    }

    _vocab = llama_model_get_vocab(_model);

    // Create context
    struct llama_context_params ctxParams = llama_context_default_params();
    ctxParams.n_ctx = nCtx > 0 ? (uint32_t)nCtx : 2048;
    ctxParams.n_threads = nThreads;
    ctxParams.n_threads_batch = nThreads;
    ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;

    _ctx = llama_init_from_model(_model, ctxParams);
    if (!_ctx) {
        NSLog(@"LlamaBridge: failed to create context");
        llama_model_free(_model);
        _model = nullptr;
        return NO;
    }

    // Greedy decoding removes sampling variance so identical prompts stay reproducible.
    _sampler = CreateDeterministicSampler();

    NSLog(@"LlamaBridge: model loaded, ctx=%d threads=%d", nCtx, nThreads);
    return YES;
}

// MARK: - Decode delay

- (void)setDecodeDelayMicroseconds:(int)us {
    _decodeDelayUs.store(us);
    NSLog(@"LlamaBridge: decode delay set to %d us", us);
}

- (void)setGenerationQoSMode:(NSInteger)mode {
    _generationQoSMode.store(mode);
    NSLog(@"LlamaBridge: generation QoS set to %s", QoSNameForMode(mode));
}

- (void)setGenerationPaused:(BOOL)paused {
    _paused.store(paused);
    NSLog(@"LlamaBridge: generation %s", paused ? "paused" : "resumed");
}

// MARK: - Generation

- (void)startGenerationWithPrompt:(NSString *)prompt
                   tokenCallback:(void (^)(NSString *token))callback
                      completion:(void (^)(void))completion {
    if (!self.isModelLoaded) {
        NSLog(@"LlamaBridge: no model loaded");
        if (completion) completion();
        return;
    }

    _cancelRequested.store(false);
    _generating.store(true);

    // Recreate the sampler so each generation starts from the same deterministic decode state.
    if (_sampler) {
        llama_sampler_free(_sampler);
    }
    _sampler = CreateDeterministicSampler();

    // Capture what we need for the background block
    struct llama_context *ctx = _ctx;
    struct llama_sampler *sampler = _sampler;
    const struct llama_vocab *vocab = _vocab;
    NSInteger qosMode = _generationQoSMode.load();
    qos_class_t qosClass = QoSClassForMode(qosMode);

    dispatch_async(dispatch_get_global_queue(qosClass, 0), ^{
        [self runGenerationLoop:prompt
                           ctx:ctx
                       sampler:sampler
                         vocab:vocab
                 tokenCallback:callback
                    completion:completion];
    });
}

- (void)runGenerationLoop:(NSString *)prompt
                     ctx:(struct llama_context *)ctx
                 sampler:(struct llama_sampler *)sampler
                   vocab:(const struct llama_vocab *)vocab
           tokenCallback:(void (^)(NSString *token))callback
              completion:(void (^)(void))completion {

    NSInteger appliedQoSMode = -1;
    auto applyQoSIfNeeded = [&]() {
        NSInteger qosMode = _generationQoSMode.load();
        if (qosMode == appliedQoSMode) {
            return;
        }

        pthread_set_qos_class_self_np(QoSClassForMode(qosMode), 0);
        appliedQoSMode = qosMode;
    };
    applyQoSIfNeeded();

    // Apply model's chat template so thinking/chat modes work (e.g. Qwen3)
    std::string formattedPrompt = [self applyChatTemplate:[prompt UTF8String]];
    const char *promptCStr = formattedPrompt.c_str();
    int promptLen = (int)formattedPrompt.size();

    NSLog(@"LlamaBridge: formatted prompt (%d chars): %.200s...", promptLen, promptCStr);

    // Wipe KV cache so each generation starts from identical state — required for
    // reproducible runs across multiple inferences on the same loaded model.
    llama_memory_clear(llama_get_memory(ctx), true);

    // Tokenize the formatted prompt (add_bos=false since template includes BOS handling)
    int nMaxTokens = promptLen + 64;
    std::vector<llama_token> tokens(nMaxTokens);
    int nTokens = llama_tokenize(vocab, promptCStr, promptLen,
                                 tokens.data(), nMaxTokens,
                                 true, true);
    if (nTokens < 0) {
        // Retry with larger buffer
        nMaxTokens = -nTokens + 64;
        tokens.resize(nMaxTokens);
        nTokens = llama_tokenize(vocab, promptCStr, promptLen,
                                 tokens.data(), nMaxTokens,
                                 true, true);
    }
    if (nTokens <= 0) {
        NSLog(@"LlamaBridge: tokenization failed");
        _generating.store(false);
        if (completion) completion();
        return;
    }
    tokens.resize(nTokens);
    NSLog(@"LlamaBridge: tokenized %d tokens", nTokens);

    llama_token eosToken = llama_vocab_eos(vocab);
    llama_token eotToken = llama_vocab_eot(vocab);  // <|im_end|> for Qwen

    // Prompt eval: feed all prompt tokens
    struct llama_batch batch = llama_batch_get_one(tokens.data(), nTokens);
    if (llama_decode(ctx, batch) != 0) {
        NSLog(@"LlamaBridge: prompt eval failed");
        _generating.store(false);
        if (completion) completion();
        return;
    }

    // Generation loop
    char pieceBuffer[128];

    while (true) {
        applyQoSIfNeeded();

        if (_cancelRequested.load()) {
            break;
        }

        while (_paused.load() && !_cancelRequested.load()) {
            usleep(10000);
        }
        if (_cancelRequested.load()) {
            break;
        }

        // Apply decode delay between tokens
        int delayUs = _decodeDelayUs.load();
        if (delayUs > 0) {
            usleep(delayUs);
        }

        // Sample next token
        llama_token newToken = llama_sampler_sample(sampler, ctx, -1);
        llama_sampler_accept(sampler, newToken);

        // Check EOS or EOT (<|im_end|>)
        if (newToken == eosToken || newToken == eotToken) {
            break;
        }

        // Convert token to text
        int pieceLen = llama_token_to_piece(vocab, newToken, pieceBuffer, sizeof(pieceBuffer) - 1, 0, true);
        if (pieceLen > 0) {
            pieceBuffer[pieceLen] = '\0';
            NSString *piece = [NSString stringWithUTF8String:pieceBuffer];
            if (piece && callback) {
                callback(piece);
            }
        }

        // Prepare next decode step with the new token
        struct llama_batch nextBatch = llama_batch_get_one(&newToken, 1);
        if (llama_decode(ctx, nextBatch) != 0) {
            NSLog(@"LlamaBridge: decode failed");
            break;
        }
    }

    _generating.store(false);
    if (completion) completion();
}

- (void)stopGeneration {
    _cancelRequested.store(true);
}

// MARK: - Chat template

- (std::string)applyChatTemplate:(const char *)userMessage {
    // Get model's built-in chat template (works for Qwen3, Llama3, etc.)
    const char *tmpl = llama_model_chat_template(_model, /*name=*/nullptr);
    std::string userMessageWithThink = std::string(userMessage) + "/think";
    
    // Build a single-turn conversation: system + user
    struct llama_chat_message messages[2];
    
    messages[0].role = "system";
    messages[0].content = "You are a helpful assistant. Provide as much detail as possible in your answers.";
    
    messages[1].role = "user";
    messages[1].content = userMessageWithThink.c_str();
    
    int nMsg = 2;

    // First call: determine required buffer size
    int32_t needed = llama_chat_apply_template(
        tmpl, messages, nMsg,
        /*add_ass=*/true,  // add assistant turn start so model begins generating
        nullptr, 0);

    if (needed <= 0) {
        // Fallback: if template application fails, return raw prompt
        NSLog(@"LlamaBridge: chat template failed, using raw prompt");
        return userMessageWithThink;
    }

    // Second call: fill buffer
    std::vector<char> buf(needed + 1);
    llama_chat_apply_template(tmpl, messages, nMsg, true, buf.data(), (int32_t)buf.size());
    buf[needed] = '\0';

    return std::string(buf.data(), needed);
}

// MARK: - Cleanup

- (void)unloadModel {
    _cancelRequested.store(true);

    // Spin-wait briefly if generating (max ~1s)
    for (int i = 0; i < 100 && _generating.load(); i++) {
        usleep(10000);
    }

    if (_sampler) {
        llama_sampler_free(_sampler);
        _sampler = nullptr;
    }
    if (_ctx) {
        llama_free(_ctx);
        _ctx = nullptr;
    }
    if (_model) {
        llama_model_free(_model);
        _model = nullptr;
    }
    _vocab = nullptr;

    llama_backend_free();
}

@end
