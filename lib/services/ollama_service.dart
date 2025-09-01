import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ollama_models.dart';

class OllamaService {
  final String baseUrl;

  OllamaService(this.baseUrl);

  Future<List<OllamaModel>> fetchModels() async {
    final uri = Uri.parse('$baseUrl/api/tags');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.reasonPhrase}',
      );
    }

    final body = json.decode(response.body);

    List items = [];
    if (body is List) {
      items = body;
    } else if (body is Map<String, dynamic>) {
      // handle several common shapes
      if (body['tags'] is List) {
        items = body['tags'];
      } else if (body['models'] is List) {
        items = body['models'];
      } else if (body['installed'] is List) {
        items = body['installed'];
      } else {
        // unknown: wrap single object
        items = [body];
      }
    } else {
      throw Exception('Unexpected response format');
    }

    return items.map((e) {
      if (e is Map<String, dynamic>) {
        return OllamaModel.fromJson(e);
      } else if (e is Map) {
        return OllamaModel.fromJson(Map<String, dynamic>.from(e));
      } else {
        return OllamaModel.fromJson({'name': e.toString()});
      }
    }).toList();
  }

  Future<String?> fetchVersion() async {
    try {
      final uri = Uri.parse('$baseUrl/api/version');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is Map && body['version'] != null) {
          return body['version'].toString();
        } else if (body is String) {
          return body;
        } else if (body is Map && body['version_string'] != null) {
          return body['version_string'].toString();
        } else {
          return body.toString();
        }
      } else {
        return 'err:${resp.statusCode}';
      }
    } catch (e) {
      return null;
    }
  }

  Future<List<RunningModel>> fetchRunningModels() async {
    try {
      final uri = Uri.parse('$baseUrl/api/ps');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        List items = [];
        if (body is List) {
          items = body;
        } else if (body is Map) {
          if (body['models'] is List) {
            items = body['models'];
          } else if (body['processes'] is List) {
            items = body['processes'];
          } else if (body['ps'] is List) {
            items = body['ps'];
          } else {
            items = [body];
          }
        }

        return items.whereType<Map>().map((item) {
          return RunningModel.fromJson(Map<String, dynamic>.from(item));
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchModelExtraInfo(String modelName) async {
    final url = Uri.parse('$baseUrl/api/show');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': modelName}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch extra info: ${response.statusCode}');
    }
  }
}
