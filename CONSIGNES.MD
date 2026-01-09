# Bases de Donnees Specialisees - Projet : comparaison Cypher 5 et Cypher 25

Le projet est a faire en binome. Vous soumettrez une archive ou un lien vers vos fichiers
sources (e.g. csv, requetes Cypher), ainsi qu’un rapport en anglais ou français au format pdf
decrivant votre travail.

## 1. Choix et import d’un jeu de donnees

Vous choisirez un jeu de donnees dans l’open data (vous pouvez par exemple en selectionner
un sur https://www.kaggle.com/datasets) ou bien vous recupererez des donnees directement
sur le web (par exemple en utilisant les librairies de la Python Data Science Stack). Veillez a
ce qu’il s’agisse de donnees connectees, pour lesquelles une implementation graphe est perti-
nente.

Vous implementerez vos donnees dans une base de donnees relationnelle PostgreSQL,
ainsi que dans une base de donnees graphe Neo4j. Veillez a ce que des proprietes numeri-
ques soient associes a certaines des arretes de votre graphe (e.g., cout, distance, date, etc.),
de facon a pouvoir travailler sur l’implementation d’algorithmes de graphe varies. N’oubliez
pas de definir soigneusement vos contraintes d’integrite et index, ainsi que d’expliciter votre
strategie d’import de donnees dans le rapport, qui devra egalement expliquer vos eventuels
choix de modelisation (relisez bien les conseils de modelisation donnes en cours, il n’est
d’ailleurs pas interdit de s’y referer dans le rapport !). Si vous avez du nettoyer vos donnees,
expliquez egalement comment vous avez procede.

## 2. Requetes
L’un des objectifs de ce projet consiste a comparer Cypher 5 avec Cypher 25. Vous com-
mencerez par examiner les requetes etudiees dans [cet article](./article/SIGMOD.MD), qui porte sur Cypher 5 et ses versions anterieures. En vous inspirant de cet [article](./article/QUERY_CHOMP_REPEAT.MD) et [celui-ci](./article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD), vous essaierez alors de pro-poser de nouvelles manieres d’ecrire dans Cypher 25, les requetes Cypher 5 pointees comme
problematiques dans le premier article. Vous testerez egalement l’evaluation de versions SQL
de certaines de ces requetes sur votre jeu de donnees relationnelles. Lorsque l’evaluation ne
termine pas sur votre jeu de donnees, vous essaierez de determiner un sous-ensemble de votre
jeu de donnees sur lequel elle termine (sous-graphe ou sous-ensemble des tuples). Vous etes
invites a etudier tout probleme de graphe qui n’aurait pas ete considere dans le premier
article, mais qui vous semble interessant.

Incluez dans votre rapport quelques plans d’execution. Qu’en concluez-vous ? Comparez en
particulier l’evaluation de requetes Cypher 5 et 25 a priori equivalentes mais utilisant des
syntaxes differentes (d’autant plus interessant si l’une s’evalue bien et l’autre non). Pour
chaque requete consideree, essayez de proposez une requete SQL equivalente : vous compare-
rez l’efficacite de l’evaluation des requetes par postgres et neo4j. En particulier, proposez au
moins une requete SQL recursive sur votre BD relationnelle, dont vous comparerez l’efficacite
avec celle d’une requete Cypher 5 ou 25 equivalente sur votre BD graphe. Essayez egalement
de trouver une requete SQL plus efficace qu’une requete Cypher, a expressivite equivalente.
Essayez d’expliquer vos resultats.

J’attends au moins les comparaisons suivantes :
- Pour une certaine propriete d’arete (par exemple, timestamp, age, poids, etc), con-
siderez une requete filtrant des chemins tels que la valeur de cette propriete soit crois-
sante sur les aretes du chemin. Utilisez un filtre negatif sur certains types de patterns
(NOT EXISTS) pour exprimer la requete dans Cypher 5 et utilisez allReduce pour
l’exprimer dans Cypher 25.
- Considerez au moins une requete Cypher 25 utilisant des quantified graph patterns
qu’il vous semblerait difficile d’ecrire sans cette fonctionnalite (proposez si possible
une ecriture sans).
- Vous considerez un ensemble de requetes calculant des plus courts chemins, non ponderes
et ponderes, vous testerez et comparerez l’ensemble des variantes disponibles dans
Cypher 5, Cypher 25 et GDS (pour GDS, il vous faudra donc en particulier creer une
projection de votre graphe transactionnel sur laquelle vous pourrez ensuite lancer vos
algorithmes). Quels sont les algorithmes utilises par les plans de neo4j ? (Commentez
en particulier la difference entre BFS unidirectionnel et bidirectionnel.)
- Essayez d’implementer directement dans Cypher 25 certains des algorithmes de graphe
disponibles dans GDS. Comparez les deux approches.

Bonus : considerez d’autres SGBDs, par exemple Memgraph qui implemente Cypher ou bien
DuckDB, qui implemente SQL PGQ.