/// Best-effort mapping from a fine-grained ImageNet label (e.g.
/// "Labrador_retriever", "backpack", "cellular_telephone") onto this app's
/// small set of lost-and-found categories.
///
/// This is a keyword heuristic, not a trained classifier — ImageNet's 1000
/// classes were never designed to line up with "Bags" or "Documents", so
/// treat this as a reasonable starting point to refine once you see real
/// predictions on real photos, not as a finished feature.
String mapImagenetLabelToCategory(String imagenetLabel) {
  final label = imagenetLabel.toLowerCase().replaceAll('_', ' ');

  const rules = <String, List<String>>{
    'Pets': [
      'dog', 'cat', 'retriever', 'terrier', 'puppy', 'kitten', 'parrot',
      'rabbit', 'hamster', 'poodle', 'spaniel', 'tabby', 'persian cat',
    ],
    'Electronics': [
      'phone', 'cellular telephone', 'laptop', 'notebook computer',
      'computer', 'camera', 'headphone', 'earphone', 'charger', 'tablet',
      'remote control', 'ipod', 'joystick',
    ],
    'Bags': ['backpack', 'purse', 'wallet', 'handbag', 'suitcase', 'bag', 'satchel'],
    'Documents': ['book', 'passport', 'binder', 'envelope', 'notebook', 'menu'],
    'Keys': ['key', 'padlock', 'lock'],
    'Jewelry': ['ring', 'necklace', 'bracelet', 'watch', 'earring', 'jewel'],
    'Clothing': [
      'shirt', 'jacket', 'coat', 'shoe', 'sneaker', 'sandal', 'hat',
      'scarf', 'sweater', 'jersey', 'cardigan', 'trouser',
    ],
  };

  for (final entry in rules.entries) {
    for (final keyword in entry.value) {
      if (label.contains(keyword)) return entry.key;
    }
  }
  return 'Other';
}
