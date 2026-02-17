.PHONY: app

app: 
	rm -r app/
	mkdir -p app/bin/
	mkdir -p app/data/
	mkdir -p app/web/
	dart compile exe -o app/bin/server.exe bin/server.dart
	cp data/superlatives.yaml app/data/
	cp web/* app/web/
