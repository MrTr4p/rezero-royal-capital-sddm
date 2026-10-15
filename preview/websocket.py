import logging
logging.basicConfig(level=logging.INFO)
from websockify.websocketproxy import ProxyRequestHandler, WebSocketProxy
from websockify.auth_plugins import AuthenticationError

class LocalOriginHandler(ProxyRequestHandler):
    def validate_connection(self):
        if self.headers.get('Origin') not in ('http://localhost:8771', 'http://127.0.0.1:8771'):
            self.send_error(403, 'Local preview origin required')
            raise AuthenticationError('Local preview origin required')
        super().validate_connection()

if __name__ == '__main__':
    WebSocketProxy(RequestHandlerClass=LocalOriginHandler, listen_host='127.0.0.1', listen_port=6071,
                   target_host='127.0.0.1', target_port=5971).start_server()
