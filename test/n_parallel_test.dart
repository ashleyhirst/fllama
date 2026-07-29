import 'package:fllama/fllama.dart';
import 'package:test/test.dart';

void main() {
  test('OpenAiRequest defaults nParallel to one', () {
    final request = OpenAiRequest(modelPath: '/tmp/model.gguf');

    expect(request.nParallel, 1);
  });

  test('FllamaInferenceRequest defaults nParallel to one', () {
    final request = FllamaInferenceRequest(
      contextSize: 4096,
      input: 'hello',
      maxTokens: 16,
      modelPath: '/tmp/model.gguf',
      numGpuLayers: 0,
      penaltyFrequency: 0,
      penaltyRepeat: 1.1,
      temperature: 0.7,
      topP: 1,
    );

    expect(request.nParallel, 1);
  });
}
