from AI import api_server
print('STARTING SERVER (debug run)')
api_server.app.run(host='127.0.0.1', port=8000, debug=False)
print('SERVER EXITED')
