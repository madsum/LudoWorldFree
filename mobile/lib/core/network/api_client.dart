import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../storage/secure_storage_service.dart';
import 'auth_interceptor.dart';

final apiClientProvider = Provider<Dio>((ref) {
  final storageService = ref.watch(secureStorageServiceProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.defaultApiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  dio.interceptors.add(AuthInterceptor(storageService));
  dio.interceptors.add(
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ),
  );

  return dio;
});
