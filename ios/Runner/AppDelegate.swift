import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let phiChannelName = "nexus/phi"
  private let ragChannelName = "nexus/rag"
  private var phiBridge: PhiOnnxBridge?
  private var ragBridge: RagBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return result
    }

    phiBridge = PhiOnnxBridge()
    ragBridge = RagBridge()

    // RAG Channel
    let ragChannel = FlutterMethodChannel(name: ragChannelName, binaryMessenger: controller.binaryMessenger)
    ragChannel.setMethodCallHandler { [weak self] call, flutterResult in
      guard let self = self else {
        flutterResult(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "loadIndex":
        let arguments = call.arguments as? [String: Any]
        self.ragBridge?.loadIndex(arguments: arguments) { success in
          DispatchQueue.main.async {
            flutterResult(success)
          }
        }

      case "search":
        guard let payload = call.arguments as? [String: Any],
              let query = payload["query"] as? String else {
          flutterResult(FlutterError(code: "INVALID_INPUT", message: "Query is required", details: nil))
          return
        }
        let topK = payload["topK"] as? Int ?? 3
        self.ragBridge?.search(query: query, topK: topK) { ids in
          DispatchQueue.main.async {
            flutterResult(ids)
          }
        }

      default:
        flutterResult(FlutterMethodNotImplemented)
      }
    }

    // Phi Channel
    let phiChannel = FlutterMethodChannel(name: phiChannelName, binaryMessenger: controller.binaryMessenger)
    phiChannel.setMethodCallHandler { [weak self] call, flutterResult in
      guard let self = self else {
        flutterResult(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "loadModel":
        let arguments = call.arguments as? [String: Any]
        self.phiBridge?.loadModel(arguments: arguments) { loadResult in
          DispatchQueue.main.async {
            switch loadResult {
            case .success:
              flutterResult(true)
            case let .failure(error):
              flutterResult(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
            }
          }
        }

      case "generate":
        guard let payload = call.arguments as? [String: Any],
              let prompt = payload["prompt"] as? String else {
          flutterResult(FlutterError(code: "INVALID_INPUT", message: "Prompt is required", details: nil))
          return
        }
        let contexts = payload["contexts"] as? [String] ?? []
        self.phiBridge?.generate(prompt: prompt, contexts: contexts) { response in
          DispatchQueue.main.async {
            flutterResult(response)
          }
        }

      default:
        flutterResult(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return result
  }
}

final class PhiOnnxBridge {
  private let fileManager = FileManager.default
  private let queue = DispatchQueue(label: "com.example.nexus.phi", qos: .userInitiated)
  private var isLoaded = false
  private var modelHandle: OpaquePointer?
  private var tokenizerHandle: OpaquePointer?
  private let maxNewTokens = 192
  private let errorDomain = "PhiOnnxBridge"

  deinit {
    queue.sync {
      resetState()
    }
  }

  func loadModel(arguments: [String: Any]?, completion: @escaping (Result<Bool, Error>) -> Void) {
    queue.async {
      do {
        guard let directoryPath = arguments?["modelDirectory"] as? String else {
          throw self.makeError(code: -2, message: "Model directory missing")
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard self.fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
          throw self.makeError(code: -3, message: "Model directory not found: \(directoryPath)")
        }

        let configURL = directoryURL.appendingPathComponent("genai_config.json")
        guard self.fileManager.fileExists(atPath: configURL.path) else {
          throw self.makeError(code: -21, message: "genai_config.json missing in \(directoryPath)")
        }

        try self.initializeModel(at: directoryURL)
        self.isLoaded = true

        DispatchQueue.main.async {
          completion(.success(true))
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func generate(prompt: String, contexts: [String], completion: @escaping (String?) -> Void) {
    queue.async {
      guard self.isLoaded, let model = self.modelHandle, let tokenizer = self.tokenizerHandle else {
        DispatchQueue.main.async { completion(nil) }
        return
      }

      do {
        let promptText = self.buildPrompt(prompt: prompt, contexts: contexts)
        let response = try self.runGeneration(model: model, tokenizer: tokenizer, prompt: promptText)
        DispatchQueue.main.async {
          completion(response)
        }
      } catch {
        DispatchQueue.main.async {
          completion(nil)
        }
      }
    }
  }

  private func initializeModel(at directory: URL) throws {
    resetState()

    try directory.path.withCString { pathPointer in
      var model: OpaquePointer?
      try check(OgaCreateModel(pathPointer, &model))
      guard let resolvedModel = model else {
        throw makeError(code: -4, message: "Failed to create model handle")
      }

      var tokenizer: OpaquePointer?
      do {
        try check(OgaCreateTokenizer(resolvedModel, &tokenizer))
      } catch {
        OgaDestroyModel(resolvedModel)
        throw error
      }
      guard let resolvedTokenizer = tokenizer else {
        OgaDestroyModel(resolvedModel)
        throw makeError(code: -5, message: "Failed to create tokenizer handle")
      }

      modelHandle = resolvedModel
      tokenizerHandle = resolvedTokenizer
    }
  }

  private func runGeneration(model: OpaquePointer, tokenizer: OpaquePointer, prompt: String) throws -> String? {
    var sequences: OpaquePointer?
    try check(OgaCreateSequences(&sequences))
    guard let promptSequences = sequences else {
      throw makeError(code: -6, message: "Failed to create sequences")
    }
    defer { OgaDestroySequences(promptSequences) }

    try prompt.withCString { textPointer in
      try check(OgaTokenizerEncode(tokenizer, textPointer, promptSequences))
    }

    let promptLength = Int(OgaSequencesGetSequenceCount(promptSequences, 0))
    guard let promptData = OgaSequencesGetSequenceData(promptSequences, 0) else {
      throw makeError(code: -7, message: "Failed to read prompt tokens")
    }
    let promptTokens = Array(UnsafeBufferPointer(start: promptData, count: promptLength))

    var params: OpaquePointer?
    try check(OgaCreateGeneratorParams(model, &params))
    guard let generatorParams = params else {
      throw makeError(code: -8, message: "Failed to create generator params")
    }
    defer { OgaDestroyGeneratorParams(generatorParams) }

    let maxLength = promptTokens.count + maxNewTokens
    try setSearchOption(params: generatorParams, name: "max_length", value: Double(maxLength))
    try setSearchOption(params: generatorParams, name: "min_length", value: 0.0)
    try setSearchOption(params: generatorParams, name: "temperature", value: 0.4)
    try setSearchOption(params: generatorParams, name: "top_p", value: 0.8)
    try setSearchOption(params: generatorParams, name: "top_k", value: 1.0)
    try setSearchOption(params: generatorParams, name: "repetition_penalty", value: 1.1)
    try setSearchOption(params: generatorParams, name: "do_sample", flag: false)

    var generator: OpaquePointer?
    try check(OgaCreateGenerator(model, generatorParams, &generator))
    guard let generatorHandle = generator else {
      throw makeError(code: -9, message: "Failed to create generator")
    }
    defer { OgaDestroyGenerator(generatorHandle) }

    try check(OgaGenerator_AppendTokenSequences(generatorHandle, promptSequences))

    var stream: OpaquePointer?
    try check(OgaCreateTokenizerStream(tokenizer, &stream))
    guard let streamHandle = stream else {
      throw makeError(code: -10, message: "Failed to create tokenizer stream")
    }
    defer { OgaDestroyTokenizerStream(streamHandle) }

    for token in promptTokens {
      _ = try? decodeToken(stream: streamHandle, token: token)
    }

    var generatedText = ""
    var tokenBudget = maxNewTokens

    while !OgaGenerator_IsDone(generatorHandle), tokenBudget > 0 {
      try check(OgaGenerator_GenerateNextToken(generatorHandle))

      var tokensPointer: UnsafePointer<Int32>?
      var tokenCount: Int = 0
      try check(OgaGenerator_GetNextTokens(generatorHandle, &tokensPointer, &tokenCount))

      if let pointer = tokensPointer, tokenCount > 0 {
        let token = pointer.pointee
        let chunk = try decodeToken(stream: streamHandle, token: token)
        generatedText.append(chunk)
        tokenBudget -= 1
      } else {
        break
      }
    }

    let fallback = try decodeFullResponse(generator: generatorHandle, tokenizer: tokenizer, promptCount: promptTokens.count)
    let trimmed = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    let result = trimmed.isEmpty ? fallback : trimmed
    return result?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func decodeFullResponse(generator: OpaquePointer, tokenizer: OpaquePointer, promptCount: Int) throws -> String? {
    let totalCount = Int(OgaGenerator_GetSequenceCount(generator, 0))
    guard totalCount > promptCount else {
      return nil
    }
    guard let fullData = OgaGenerator_GetSequenceData(generator, 0) else {
      return nil
    }

    let totalTokens = Array(UnsafeBufferPointer(start: fullData, count: totalCount))
    let responseTokens = Array(totalTokens.dropFirst(promptCount))
    if responseTokens.isEmpty {
      return nil
    }

    return try responseTokens.withUnsafeBufferPointer { buffer -> String? in
      guard let baseAddress = buffer.baseAddress else { return nil }
      var outputPointer: UnsafePointer<CChar>?
      try check(OgaTokenizerDecode(tokenizer, baseAddress, buffer.count, &outputPointer))
      guard let cString = outputPointer else {
        return nil
      }
      defer { OgaDestroyString(cString) }
      return String(cString: cString)
    }
  }

  private func setSearchOption(params: OpaquePointer, name: String, value: Double) throws {
    try name.withCString { keyPointer in
      try check(OgaGeneratorParamsSetSearchNumber(params, keyPointer, value))
    }
  }

  private func setSearchOption(params: OpaquePointer, name: String, flag: Bool) throws {
    try name.withCString { keyPointer in
      try check(OgaGeneratorParamsSetSearchBool(params, keyPointer, flag))
    }
  }

  private func decodeToken(stream: OpaquePointer, token: Int32) throws -> String {
    var chunkPointer: UnsafePointer<CChar>?
    try check(OgaTokenizerStreamDecode(stream, token, &chunkPointer))
    guard let cString = chunkPointer else {
      return ""
    }
    return String(cString: cString)
  }

  private func buildPrompt(prompt: String, contexts: [String]) -> String {
    let systemPrompt = "Ты — русскоязычный ассистент Nexus. Отвечай строго на русском языке, дружелюбно и по делу. Не задавай встречных вопросов без необходимости и не выдумывай новые темы. Если данных недостаточно, честно сообщи об этом. Формат ответа — максимум 2-3 предложения.\n\n"

    let contextBlock: String
    if contexts.isEmpty {
      contextBlock = "[Контекст]\nнет дополнительного контекста"
    } else {
      let merged = contexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n\n")
      contextBlock = "[Контекст]\n\(merged)"
    }

    return "\(systemPrompt)\(contextBlock)\n\n[Вопрос]\n\(prompt)\n\n[Ответ]"
  }

  private func check(_ result: UnsafeMutablePointer<OgaResult>?) throws {
    guard let result else { return }
    defer { OgaDestroyResult(result) }
    if let messagePointer = OgaResultGetError(result) {
      let message = String(cString: messagePointer)
      throw makeError(code: -100, message: message)
    } else {
      throw makeError(code: -100, message: "Unknown ONNX Runtime error")
    }
  }

  private func resetState() {
    if let tokenizer = tokenizerHandle {
      OgaDestroyTokenizer(tokenizer)
    }
    if let model = modelHandle {
      OgaDestroyModel(model)
    }
    tokenizerHandle = nil
    modelHandle = nil
    isLoaded = false
  }

  private func makeError(code: Int, message: String) -> NSError {
    NSError(domain: errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

// MARK: - RAG Bridge

final class RagBridge {
  private let fileManager = FileManager.default
  private let queue = DispatchQueue(label: "com.example.nexus.rag", qos: .userInitiated)
  private var isLoaded = false
  private var embeddings: [Float]?
  private var numVectors: Int = 0
  private var embeddingDim: Int = 384
  private var vocabulary: [String: Int]?
  private var mergeRanks: [String: Int]?
  private var ortEnv: OpaquePointer?
  private var embeddingSession: OpaquePointer?
  
  deinit {
    queue.sync {
      resetState()
    }
  }
  
  func loadIndex(arguments: [String: Any]?, completion: @escaping (Bool) -> Void) {
    queue.async {
      guard let indexPath = arguments?["indexPath"] as? String else {
        completion(false)
        return
      }
      
      let embeddingModelPath = arguments?["embeddingModelPath"] as? String
      let tokenizerPath = arguments?["tokenizerPath"] as? String
      self.embeddingDim = arguments?["embeddingDim"] as? Int ?? 384
      
      let embeddingsFile = URL(fileURLWithPath: indexPath)
      
      guard self.fileManager.fileExists(atPath: embeddingsFile.path) else {
        print("[RAG] Embeddings file not found: \(embeddingsFile.path)")
        completion(false)
        return
      }
      
      do {
        // Загружаем embeddings
        let data = try Data(contentsOf: embeddingsFile)
        let floatCount = data.count / 4
        self.numVectors = floatCount / self.embeddingDim
        
        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        self.embeddings = floats
        
        print("[RAG] Loaded \(self.numVectors) vectors of dim \(self.embeddingDim)")
        
        // Загружаем токенизатор
        if let tokPath = tokenizerPath {
          self.loadTokenizer(path: tokPath)
        }
        
        // Загружаем embedding модель
        if let modelPath = embeddingModelPath,
           self.fileManager.fileExists(atPath: modelPath) {
          self.loadEmbeddingModel(path: modelPath)
        }
        
        self.isLoaded = true
        completion(true)
      } catch {
        print("[RAG] Failed to load index: \(error)")
        completion(false)
      }
    }
  }
  
  func search(query: String, topK: Int, completion: @escaping ([Int]?) -> Void) {
    queue.async {
      guard self.isLoaded, let embeddings = self.embeddings else {
        completion(nil)
        return
      }
      
      guard let queryEmbedding = self.computeEmbedding(text: query) else {
        print("[RAG] Failed to compute query embedding")
        completion(nil)
        return
      }
      
      // Косинусное сходство
      var scores = [Float](repeating: 0, count: self.numVectors)
      for i in 0..<self.numVectors {
        var dot: Float = 0
        let offset = i * self.embeddingDim
        for j in 0..<self.embeddingDim {
          dot += queryEmbedding[j] * embeddings[offset + j]
        }
        scores[i] = dot
      }
      
      // Топ-K
      let indices = scores.enumerated()
        .sorted { $0.element > $1.element }
        .prefix(topK)
        .map { $0.offset + 1 } // ID начинаются с 1
      
      completion(Array(indices))
    }
  }
  
  private func loadTokenizer(path: String) {
    guard let data = fileManager.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let model = json["model"] as? [String: Any],
          let vocabDict = model["vocab"] as? [String: Int],
          let mergesArray = model["merges"] as? [String] else {
      print("[RAG] Failed to parse tokenizer")
      return
    }
    
    vocabulary = vocabDict
    
    var ranks = [String: Int]()
    for (index, merge) in mergesArray.enumerated() {
      ranks[merge] = index
    }
    mergeRanks = ranks
    
    print("[RAG] Tokenizer loaded: \(vocabDict.count) tokens, \(mergesArray.count) merges")
  }
  
  private func loadEmbeddingModel(path: String) {
    // ONNX Runtime для embedding модели
    // Используем стандартный ONNX Runtime API
    var env: OpaquePointer?
    let status = OrtCreateEnv(ORT_LOGGING_LEVEL_WARNING, "RagBridge", &env)
    guard status == nil, let environment = env else {
      print("[RAG] Failed to create ORT environment")
      return
    }
    ortEnv = environment
    
    var sessionOptions: OpaquePointer?
    _ = OrtCreateSessionOptions(&sessionOptions)
    
    var session: OpaquePointer?
    let sessionStatus = path.withCString { pathPtr in
      OrtCreateSession(environment, pathPtr, sessionOptions, &session)
    }
    
    if sessionStatus == nil, let sess = session {
      embeddingSession = sess
      print("[RAG] Embedding model loaded")
    } else {
      print("[RAG] Failed to load embedding model")
    }
    
    if let opts = sessionOptions {
      OrtReleaseSessionOptions(opts)
    }
  }
  
  private func computeEmbedding(text: String) -> [Float]? {
    guard embeddingSession != nil else {
      print("[RAG] Embedding session not loaded")
      return nil
    }
    
    let tokens = tokenize(text: text)
    guard !tokens.isEmpty else { return nil }
    
    // Для упрощения используем fallback без ONNX если модель сложная
    // В полной реализации здесь был бы вызов ONNX Runtime
    // Пока возвращаем nil чтобы использовать fallback
    return computeEmbeddingWithONNX(tokens: tokens)
  }
  
  private func computeEmbeddingWithONNX(tokens: [Int64]) -> [Float]? {
    guard let session = embeddingSession, let env = ortEnv else {
      return nil
    }
    
    // Создаём входные тензоры
    let inputIds = tokens
    let attentionMask = [Int64](repeating: 1, count: tokens.count)
    
    var memoryInfo: OpaquePointer?
    _ = OrtCreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo)
    guard let memInfo = memoryInfo else { return nil }
    defer { OrtReleaseMemoryInfo(memInfo) }
    
    let shape: [Int64] = [1, Int64(tokens.count)]
    
    // Input IDs tensor
    var inputIdsTensor: OpaquePointer?
    _ = inputIds.withUnsafeBufferPointer { buffer in
      OrtCreateTensorWithDataAsOrtValue(
        memInfo,
        UnsafeMutableRawPointer(mutating: buffer.baseAddress),
        buffer.count * MemoryLayout<Int64>.size,
        shape, 2,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
        &inputIdsTensor
      )
    }
    guard let idsTensor = inputIdsTensor else { return nil }
    defer { OrtReleaseValue(idsTensor) }
    
    // Attention mask tensor
    var attentionMaskTensor: OpaquePointer?
    _ = attentionMask.withUnsafeBufferPointer { buffer in
      OrtCreateTensorWithDataAsOrtValue(
        memInfo,
        UnsafeMutableRawPointer(mutating: buffer.baseAddress),
        buffer.count * MemoryLayout<Int64>.size,
        shape, 2,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
        &attentionMaskTensor
      )
    }
    guard let maskTensor = attentionMaskTensor else { return nil }
    defer { OrtReleaseValue(maskTensor) }
    
    // Run inference
    let inputNames = ["input_ids", "attention_mask"]
    let outputNames = ["last_hidden_state"]
    var outputs: [OpaquePointer?] = [nil]
    
    let runStatus = inputNames[0].withCString { inputName0 in
      inputNames[1].withCString { inputName1 in
        outputNames[0].withCString { outputName in
          var inputNamesPtr: [UnsafePointer<CChar>?] = [
            UnsafePointer(strdup(inputName0)),
            UnsafePointer(strdup(inputName1))
          ]
          var outputNamesPtr: [UnsafePointer<CChar>?] = [UnsafePointer(strdup(outputName))]
          var inputs: [OpaquePointer?] = [idsTensor, maskTensor]
          
          defer {
            inputNamesPtr.forEach { free(UnsafeMutablePointer(mutating: $0)) }
            outputNamesPtr.forEach { free(UnsafeMutablePointer(mutating: $0)) }
          }
          
          return OrtRun(
            session,
            nil,
            &inputNamesPtr,
            &inputs,
            2,
            &outputNamesPtr,
            1,
            &outputs
          )
        }
      }
    }
    
    guard runStatus == nil else {
      print("[RAG] ONNX Run failed")
      return nil
    }
    
    guard let output = outputs[0] else { return nil }
    defer { OrtReleaseValue(output) }
    
    // Извлекаем данные
    var floatData: UnsafeMutablePointer<Float>?
    _ = OrtGetTensorMutableData(output, UnsafeMutableRawPointer(&floatData))
    
    guard let data = floatData else { return nil }
    
    // Mean pooling
    var embedding = [Float](repeating: 0, count: embeddingDim)
    let seqLen = tokens.count
    
    for i in 0..<seqLen {
      for j in 0..<embeddingDim {
        embedding[j] += data[i * embeddingDim + j]
      }
    }
    
    for j in 0..<embeddingDim {
      embedding[j] /= Float(seqLen)
    }
    
    // Нормализация
    var norm: Float = 0
    for j in 0..<embeddingDim {
      norm += embedding[j] * embedding[j]
    }
    norm = sqrt(norm)
    
    if norm > 0 {
      for j in 0..<embeddingDim {
        embedding[j] /= norm
      }
    }
    
    return embedding
  }
  
  private func tokenize(text: String) -> [Int64] {
    guard let vocab = vocabulary, let ranks = mergeRanks else {
      return fallbackTokenize(text: text)
    }
    
    var tokens = [Int64]()
    
    // BOS token
    if let bos = vocab["<s>"] {
      tokens.append(Int64(bos))
    }
    
    // Разбиваем на слова
    let words = text.components(separatedBy: .whitespaces)
    var isFirst = true
    
    for word in words {
      if word.isEmpty { continue }
      
      let wordTokens = bpeEncode(word: word, vocab: vocab, ranks: ranks, isFirstWord: isFirst)
      
      for token in wordTokens {
        if let tokenId = vocab[token] {
          tokens.append(Int64(tokenId))
        } else if let unk = vocab["<unk>"] {
          tokens.append(Int64(unk))
        }
        
        if tokens.count >= 510 { break }
      }
      
      if tokens.count >= 510 { break }
      isFirst = false
    }
    
    // EOS token
    if let eos = vocab["</s>"] {
      tokens.append(Int64(eos))
    }
    
    return tokens
  }
  
  private func bpeEncode(word: String, vocab: [String: Int], ranks: [String: Int], isFirstWord: Bool) -> [String] {
    if word.isEmpty { return [] }
    
    // Добавляем ▁ в начало слова
    let processedWord: String
    if word.trimmingCharacters(in: .whitespaces).isEmpty {
      processedWord = word
    } else if isFirstWord || word.hasPrefix(" ") {
      processedWord = "▁" + word.trimmingCharacters(in: .whitespaces)
    } else {
      processedWord = word
    }
    
    if processedWord.isEmpty { return [] }
    
    // Разбиваем на символы
    var pieces = processedWord.map { String($0) }
    
    // Итеративно применяем BPE
    while pieces.count > 1 {
      var bestPair: (String, String)?
      var bestRank = Int.max
      var bestIndex = -1
      
      for i in 0..<(pieces.count - 1) {
        let pair = "\(pieces[i]) \(pieces[i + 1])"
        if let rank = ranks[pair], rank < bestRank {
          bestRank = rank
          bestPair = (pieces[i], pieces[i + 1])
          bestIndex = i
        }
      }
      
      guard let pair = bestPair else { break }
      
      let merged = pair.0 + pair.1
      pieces[bestIndex] = merged
      pieces.remove(at: bestIndex + 1)
    }
    
    return pieces
  }
  
  private func fallbackTokenize(text: String) -> [Int64] {
    var tokens = [Int64]()
    tokens.append(0) // <s>
    for char in text.prefix(510) {
      tokens.append(Int64(min(max(Int(char.asciiValue ?? 0), 0), 30000)))
    }
    tokens.append(2) // </s>
    return tokens
  }
  
  private func resetState() {
    isLoaded = false
    embeddings = nil
    vocabulary = nil
    mergeRanks = nil
    
    if let session = embeddingSession {
      OrtReleaseSession(session)
    }
    embeddingSession = nil
    
    if let env = ortEnv {
      OrtReleaseEnv(env)
    }
    ortEnv = nil
  }
}
