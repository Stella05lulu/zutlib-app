import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;
GoTrueClient get auth => Supabase.instance.client.auth;

String? get currentUserId => auth.currentUser?.id;
bool get isVerified => auth.currentUser?.emailConfirmedAt != null;
