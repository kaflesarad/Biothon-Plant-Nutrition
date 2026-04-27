from AI import api_server
print('\n'.join(sorted(str(r) for r in api_server.app.url_map.iter_rules())))
