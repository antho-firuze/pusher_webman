/// Represents the options for the authentication.
class PusherAuth {
  /// The endpoint for the authentication.
  final String endpoint;

  /// The headers for the authentication (default: `{'Accept': 'application/json'}`).
  final Map<String, String> headers;

  const PusherAuth(
    this.endpoint, {
    this.headers = const {
      'Accept': 'application/json',
    },
  });

  /// Returns a new [PusherAuth] with the given endpoint.
  @override
  String toString() {
    return 'AuthOptions(endpoint: $endpoint, headers: $headers)';
  }
}
