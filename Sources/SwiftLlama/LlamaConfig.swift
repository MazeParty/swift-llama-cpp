import Foundation
import Darwin

public struct LlamaConfig: Equatable, Sendable {
    public enum FlashAttention: Equatable, Sendable {
        /// Lets llama.cpp decide per backend and model.
        case automatic
        case enabled
        case disabled
    }

    /// Element type of the key and value caches. Quantized caches need Flash Attention.
    public enum CacheType: Equatable, Sendable {
        case f16
        case q8_0
        case q4_0
    }

    public let batchSize: UInt32
    public let maxTokenCount: UInt32
    public let useGPU: Bool
    /// Physical decode batch, independently of the logical prompt batch.
    public let microBatchSize: UInt32?
    /// Nil selects one thread for GPU and the performance core count for CPU.
    public let nThreads: Int32?
    public let nThreadsBatch: Int32?
    public let flashAttention: FlashAttention
    public let cacheType: CacheType

    public init(
        batchSize: UInt32,
        maxTokenCount: UInt32,
        useGPU: Bool = true,
        microBatchSize: UInt32? = nil,
        nThreads: Int32? = nil,
        nThreadsBatch: Int32? = nil,
        flashAttention: FlashAttention = .automatic,
        cacheType: CacheType = .f16
    ) {
        self.batchSize = batchSize
        self.maxTokenCount = maxTokenCount
        self.useGPU = useGPU
        self.microBatchSize = microBatchSize
        self.nThreads = nThreads
        self.nThreadsBatch = nThreadsBatch
        self.flashAttention = flashAttention
        self.cacheType = cacheType
    }

    static var cpuThreadCount: Int32 {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return count
        }
        return Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
    }
}
