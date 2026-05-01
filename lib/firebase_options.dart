import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Evren Tarım Market projesi için iOS desteği eklenmiş güncel versiyon.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS: // iOS için bu yönlendirme ŞART!
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBZ7s46uofpQzvCPetTfwDZv6qM2lS0Xdk',
    appId: '1:83830242468:web:757e1...',
    messagingSenderId: '83830242468',
    projectId: 'evrentarimmarket',
    authDomain: 'evrentarimmarket.firebaseapp.com',
    storageBucket: 'evrentarimmarket.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBZ7s46uofpQzvCPetTfwDZv6qM2lS0Xdk',
    appId: '1:83830242468:android:3bb6df2a93ba14f305fa31',
    messagingSenderId: '83830242468',
    projectId: 'evrentarimmarket',
    storageBucket: 'evrentarimmarket.appspot.com',
  );

  // iOS yapılandırması buraya eklendi
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBZ7s46uofpQzvCPetTfwDZv6qM2lS0Xdk',
    appId: '1:83830242468:ios:3bb6df2a93ba14f305fa31', // iOS App ID
    messagingSenderId: '83830242468',
    projectId: 'evrentarimmarket',
    storageBucket: 'evrentarimmarket.appspot.com',
    iosBundleId: 'com.evrentarim.evrenTarimMarket',
  );
}