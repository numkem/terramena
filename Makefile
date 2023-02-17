sonarqube:
	nix-shell -p sonar-scanner-cli --run 'sonar-scanner -Dsonar.projectKey=numkem_terramena_AYY4P87j8f_oyHBbVREL -Dsonar.sources=. -Dsonar.host.url=https://sonarqube.numkem.org -Dsonar.login=sqp_d7bbc18c5d5170c4558c3972f0ecac0c763c77e3'
