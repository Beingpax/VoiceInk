"""Insert Japanese punctuation into original text using a local Horizon ONNX model.

No model code is executed and no download occurs at runtime. Original characters,
including existing punctuation and whitespace, are copied without modification.
"""
import json
from pathlib import Path
import re
import threading

CJK = re.compile(r'[぀-ヿ㐀-鿿豈-﫿]')
MARKS = re.compile(r'[.,;:!?。，、；：！？؟،¿¡…।॥۔።፣፧]')
OUTPUT_MARKS = {'.': '。', ',': '、', '?': '？', ':': '：', '-': '——'}


def prepare(text):
    positions = []
    for i, char in enumerate(text):
        numeric = char in '.,:' and 0 < i < len(text)-1 and text[i-1].isdigit() and text[i+1].isdigit()
        if numeric or not MARKS.fullmatch(char):
            positions.append(i)
    return ''.join(text[i] for i in positions), positions


def insert_predictions(text, cleaned, positions, labels):
    insertions = {}
    for end, label in sorted(labels.items()):
        if label == '0':
            continue
        if label not in OUTPUT_MARKS or not 0 < end <= len(positions):
            raise ValueError('Invalid punctuation prediction')
        if not (end == len(cleaned) or cleaned[end].isspace() or CJK.match(cleaned[end-1])):
            continue
        at = positions[end-1] + 1
        # Do not insert a mark across an existing mark, even one of several.
        if at < len(text) and MARKS.fullmatch(text[at]):
            continue
        insertions[at] = OUTPUT_MARKS[label]
    return ''.join(char + insertions.get(i+1, '') for i, char in enumerate(text))


class Punctuator:
    def __init__(self, model_directory):
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        ort.disable_telemetry_events()
        directory = Path(model_directory)
        self.np = np
        self.tokenizer = Tokenizer.from_file(str(directory / 'tokenizer.json'))
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        self.session = ort.InferenceSession(str(directory / 'onnx/model_quantized.onnx'),
            sess_options=options, providers=['CPUExecutionProvider'])
        self.id2label = json.loads((directory / 'config.json').read_text())['id2label']
        self.lock = threading.Lock()
        self.bos = self.tokenizer.token_to_id('<bos>')
        self.eos = self.tokenizer.token_to_id('<eos>')
        if self.bos is None or self.eos is None:
            raise ValueError('Missing boundary tokens')

    def _labels(self, text):
        encoded = self.tokenizer.encode(text, add_special_tokens=False)
        predictions, start = {}, 0
        while start < len(encoded.ids):
            end = min(start + 400, len(encoded.ids))
            ids = self.np.array([[self.bos] + encoded.ids[start:end] + [self.eos]], dtype=self.np.int64)
            feed = {}
            for item in self.session.get_inputs():
                if item.name == 'input_ids': feed[item.name] = ids
                elif item.name == 'attention_mask': feed[item.name] = self.np.ones_like(ids)
                else: raise ValueError('Unsupported ONNX input')
            predicted = self.session.run(None, feed)[0][0, 1:-1].argmax(-1).tolist()
            keep_to = end if end == len(encoded.ids) else end - 50
            for k in range(start, keep_to):
                s, e = encoded.offsets[k]
                if e > s:
                    predictions[e] = self.id2label[str(predicted[k-start])]
            if end == len(encoded.ids): break
            start = keep_to
        return predictions

    def __call__(self, text):
        if not text or len(text) > 16000:
            return text
        cleaned, positions = prepare(text)
        if not cleaned.strip():
            return text
        with self.lock:
            predictions = self._labels(cleaned)
        return insert_predictions(text, cleaned, positions, predictions)
