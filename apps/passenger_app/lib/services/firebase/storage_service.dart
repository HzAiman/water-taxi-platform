import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage;

  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  Reference ref(String path) => _storage.ref(path);
}
