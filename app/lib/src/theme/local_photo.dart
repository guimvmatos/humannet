/// Foto de fundo guardada só neste aparelho. No Android vira um arquivo; na
/// versão web (sem sistema de arquivos), fica guardada como texto (data URL).
library;

export 'local_photo_io.dart' if (dart.library.js_interop) 'local_photo_web.dart';
