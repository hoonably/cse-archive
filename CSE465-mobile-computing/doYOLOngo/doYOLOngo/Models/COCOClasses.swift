import Foundation

/// All 80 COCO class names, index-aligned.
let cocoClasses: [String] = [
    "person", "bicycle", "car", "motorcycle", "airplane",
    "bus", "train", "truck", "boat", "traffic light",
    "fire hydrant", "stop sign", "parking meter", "bench", "bird",
    "cat", "dog", "horse", "sheep", "cow",
    "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat",
    "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
    "wine glass", "cup", "fork", "knife", "spoon",
    "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut",
    "cake", "chair", "couch", "potted plant", "bed",
    "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven",
    "toaster", "sink", "refrigerator", "book", "clock",
    "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
]

/// Alternate spoken forms → canonical COCO class name
let voiceAliasMap: [String: String] = [
    // person
    "person": "person", "people": "person", "human": "person", "man": "person",
    "woman": "person", "child": "person",
    // vehicles
    "bicycle": "bicycle", "bike": "bicycle",
    "car": "car", "automobile": "car",
    "motorcycle": "motorcycle", "motorbike": "motorcycle",
    "airplane": "airplane", "plane": "airplane",
    "bus": "bus", "truck": "truck", "train": "train", "boat": "boat",
    // animals
    "bird": "bird", "cat": "cat", "dog": "dog", "horse": "horse",
    "sheep": "sheep", "cow": "cow", "elephant": "elephant", "bear": "bear",
    "zebra": "zebra", "giraffe": "giraffe",
    // common objects
    "backpack": "backpack", "bag": "backpack", "handbag": "handbag",
    "umbrella": "umbrella", "suitcase": "suitcase", "luggage": "suitcase",
    "bottle": "bottle", "botel": "bottle", "bodle": "bottle", "border": "bottle", "butter": "bottle", "voter": "bottle", "portal": "bottle",
    "cup": "cup", "mug": "cup", "cop": "cup", "cub": "cup", "cap": "cup",
    "fork": "fork", "knife": "knife", "spoon": "spoon", "bowl": "bowl",
    "banana": "banana", "apple": "apple", "sandwich": "sandwich",
    "orange": "orange", "pizza": "pizza", "donut": "donut", "cake": "cake",
    "chair": "chair", "couch": "couch", "sofa": "couch",
    "bed": "bed", "table": "dining table", "desk": "dining table",
    "toilet": "toilet", "tv": "tv", "television": "tv", "monitor": "tv",
    "laptop": "laptop", "computer": "laptop", "notebook": "laptop",
    "mouse": "mouse", "keyboard": "keyboard",
    "phone": "cell phone", "cellphone": "cell phone", "mobile": "cell phone",
    "book": "book", "clock": "clock", "vase": "vase",
    "remote": "remote", "scissors": "scissors",
    "teddy": "teddy bear", "teddy bear": "teddy bear",
    // sports
    "ball": "sports ball", "kite": "kite", "skateboard": "skateboard",
    "surfboard": "surfboard",
]

/// Resolve a spoken word to a COCO class name using exact match first, then fuzzy match.
func resolveVoiceAliasFuzzy(_ word: String) -> String? {
    let lower = word.lowercased().trimmingCharacters(in: .whitespaces)
    if let alias = voiceAliasMap[lower] { return alias }
    if cocoClasses.contains(lower) { return lower }
    
    // Fuzzy matching candidates
    var allCandidates = Set(cocoClasses)
    for key in voiceAliasMap.keys {
        allCandidates.insert(key)
    }
    
    let maxDist = max(4, lower.count) // Significantly relaxed to always find the closest candidate
    if let best = findClosestMatch(for: lower, candidates: Array(allCandidates), maxDistance: maxDist) {
        return voiceAliasMap[best] ?? best
    }
    
    return nil
}

// MARK: - Levenshtein Distance Algorithm
private func levenshteinDistance(s: String, t: String) -> Int {
    if s.isEmpty { return t.count }
    if t.isEmpty { return s.count }

    let sArray = Array(s)
    let tArray = Array(t)
    var d = [[Int]](repeating: [Int](repeating: 0, count: tArray.count + 1), count: sArray.count + 1)

    for i in 0...sArray.count { d[i][0] = i }
    for j in 0...tArray.count { d[0][j] = j }

    for i in 1...sArray.count {
        for j in 1...tArray.count {
            let cost = sArray[i - 1] == tArray[j - 1] ? 0 : 1
            d[i][j] = min(
                d[i - 1][j] + 1,      // deletion
                d[i][j - 1] + 1,      // insertion
                d[i - 1][j - 1] + cost // substitution
            )
        }
    }
    return d[sArray.count][tArray.count]
}

func findClosestMatch(for word: String, candidates: [String], maxDistance: Int) -> String? {
    var bestMatch: String? = nil
    var minDistance = Int.max
    
    for candidate in candidates {
        // Skip calculation if word length difference is already greater than maxDistance
        guard abs(word.count - candidate.count) <= maxDistance else { continue }
        
        let dist = levenshteinDistance(s: word, t: candidate)
        if dist < minDistance && dist <= maxDistance {
            minDistance = dist
            bestMatch = candidate
        }
    }
    return bestMatch
}
