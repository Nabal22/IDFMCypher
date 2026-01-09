Title: Solve Hard Graph Problems With Cypher 25

URL Source: https://neo4j.com/blog/developer/solve-hard-graph-problems-with-cypher-25/

Published Time: 2025-10-16T19:59:20+00:00

Markdown Content:
Graphs are a powerful way to model complex relationships, from social networks to supply chains. As a developer at Neo4j, I love testing Cypher’s capabilities with [challenges](https://github.com/halftermeyer/advent-of-code-repo-list/blob/main/README.md) like the [Advent of Code (AoC) 2021 Day 12 puzzle](https://adventofcode.com/2021/day/12), which involves finding all valid paths through a submarine cave system with constraints on visiting small caves.

In 2021, solving this puzzle with Cypher was a grind, requiring complex graph transformations and heavy filtering, taking 2 minutes and 24 seconds to run. With Cypher 25’s new [**`REPEATABLE ELEMENTS`**](https://neo4j.com/docs/cypher-manual/25/patterns/match-modes/#repeatable-elements) match mode and [**`allReduce`**](https://neo4j.com/docs/cypher-manual/25/functions/predicate/#functions-allreduce) function, the same puzzle is solved in just 1.2 seconds—a **120x speedup**!

For developers and customers, these features mean simpler queries, faster performance, and the ability to tackle difficult graph problems with ease.

Let’s explore how [Cypher 25](https://neo4j.com/blog/developer/cypher-versioning/) offers this power, using AoC Day 12 as a case study, and why it’s _time to revisit old assumptions_ about what Cypher can do.

The 2021 Challenge: Wrestling With DIFFERENT RELATIONSHIPS Mode
---------------------------------------------------------------

Each of the 25 days of an AoC challenge is a two-part programming puzzle in which the second part is similar to the first, but with some additional complexity. The AoC 2021 Day 12 puzzle models a submarine cave system as a graph, with `Cave` nodes connected by bidirectional `CONNECTED_TO` relationships. In the first part of the puzzle, big caves (uppercase names) can be visited unlimited times, while small caves can be visited only once. Then, in the second part, small caves can still be visited once, except for one that can be visited twice. In 2021, Cypher’s only (default) match mode was `DIFFERENT RELATIONSHIPS`, which ensured that each relationship was traversed at most once per path, while nodes could be revisited freely.

This was useful for avoiding redundant edge traversals but didn’t address the puzzle’s core challenge: constraining _node_ visits for small caves.

The 2021 Approach
-----------------

To handle these node constraints, I had to refactor the graph extensively and rely on post-traversal filtering.

**Graph refactoring**:

*   **Eliminated big caves**: Replaced paths like `Small1-[:CONNECTED_TO]-Big-[:CONNECTED_TO]-Small2` with direct `Small1-[:CONNECTED_TO {via: Big.name}]->Small2` edges.
*   **Added loops**: For the second part, created `LOOP` relationships (e.g., `Small-[:LOOP {via: Big.name}]->Small`) to model small cave revisits, as `DIFFERENT RELATIONSHIPS` didn’t allow repeated relationship traversals.
*   **Created back edges**: Added reverse `CONNECTED_TO` edges for small caves to enable undirected traversal.
*   **Pruned leaves**: Removed small cave leaf nodes (degree 1) to simplify the first part of the graph.

![Image 1](https://cdn-images-1.medium.com/max/1024/1*S5utEBGWDiMKyjvIGi4nLA.png)

I was proud enough of my refactoring-centric solution to post it on Twitter 2021

**Post-filtering**: Used APOC procedures to enforce node constraints after traversal:

*   `apoc.coll.occurrences` checked node visit counts (e.g., small caves visited twice at most).
*   `apoc.coll.duplicates` ensured that only one small cave was visited twice in the second part.

![Image 2](https://cdn-images-1.medium.com/max/1001/1*WNSS88LwVavBNjmBhScBLw.png)

Natural graph

![Image 3](https://cdn-images-1.medium.com/max/867/1*UbXIVw88HJqtFPrFZLm5og.png)

Refactored undirected graph

The second part’s query:

`MATCH p = (s:Cave {name:"start"})-[:CONNECTED_TO|LOOP*0..7]-(e:Cave {name:"end"})WITH p, [x in apoc.coll.duplicates(nodes(p)) | x.name] as duplWHERE all(c IN nodes(p) WHERE apoc.coll.occurrences(nodes(p), c) <= 2)AND size(dupl) <= 1AND NOT "start" IN duplAND NOT "end" IN duplWITH DISTINCT [n IN nodes(p) | n.name] AS smalls, [r IN relationships(p) | r.via] AS viasRETURN count(*);`
This query:

*   Used `[:CONNECTED_TO|LOOP*0..7]` under `DIFFERENT RELATIONSHIPS`, ensuring that each relationship was traversed once per path.
*   Generated a massive set of paths due to node revisits, then filtered them with costly APOC functions.
*   Required complex graph transformations, adding preprocessing overhead.

The result? A 144-second runtime, driven by exponential path exploration and heavy post-filtering. It would have been much worse had I not known a valid solution was at most seven hops deep. This meant hours of engineering to encode constraints into the graph, making the solution feel more like a workaround than a natural query.

Cypher 25: Simplified Queries and Blazing Performance
-----------------------------------------------------

Cypher 25 introduces the `REPEATABLE ELEMENTS` match mode and `allReduce` function (see [Query, Chomp, Repeat](https://neo4j.com/blog/developer/query-chomp-repeat/)), enabling you to solve complex path-finding problems like AoC Day 12 on the _original graph_ with a single, declarative query:

`CYPHER 25 runtime=parallelMATCH REPEATABLE ELEMENTS path = (:Start)((xs:!End)--(:!Start)){0,100000}(e:End)WHERE allReduce(  small_visited = [],  x IN xs | CASE WHEN x:Big THEN small_visited ELSE small_visited+[x] END,  size(small_visited) <= size(apoc.coll.toSet(small_visited)) + 1)RETURN count(path) AS part_2;`
This query runs in just 1.2 _seconds_ — a 120x speedup!

Empowering Developers and Delivering Value
------------------------------------------

### REPEATABLE ELEMENTS: Flexibility Without Refactoring

Unlike `DIFFERENT RELATIONSHIPS`, which limits relationships to one traversal per path, `REPEATABLE ELEMENTS` allows nodes and relationships to be traversed multiple times. For AoC Day 12, this flexibility is critical, as the puzzle requires revisiting small caves and their connecting relationships to model the “one small cave visited twice” rule. The pattern `(:Start)((xs:!End)--(:!Start)){0,100000}(e:End)` with `REPEATABLE ELEMENTS`:

*   Enables paths where small caves and relationships can be revisited, eliminating the need for 2021’s graph refactoring (e.g., `LOOP` edges and back edges).
*   Expands the search space compared to `DIFFERENT RELATIONSHIPS`, allowing more paths to be considered.

This larger search space could lead to path explosion, but `allReduce`, which is applied during traversal, ensures performance remains stellar.

### allReduce: Pruning Dead Branches During Traversal

The `allReduce` function is the secret sauce for taming the expanded search space. It tracks small cave visits during traversal by building a `small_visited` list, adding only small cave names (skipping`:Big` caves via the `CASE` statement). The condition `size(small_visited) <= size(apoc.coll.toSet(small_visited)) + 1` ensures that exactly one small cave can be visited twice, pruning paths that violate this rule _during_ traversal.

This is a massive improvement over 2021’s post-filtering with `apoc.coll.occurrences` and `apoc.coll.duplicates`, which processed huge path sets after traversal. The pruning is so effective that I could set a massive depth bound of 100,000 without worrying about performance, as `allReduce` reduces the search space from millions to thousands of paths, driving the 1.2-second runtime.

### Declarative Power

Cypher 25’s query is _declarative_ — you describe _what_ they want (valid paths), rather than _how_ to compute it. This contrasts with 2021’s procedural approach, where I had to engineer the graph to encode constraints due to `DIFFERENT RELATIONSHIPS`. The synergy of `REPEATABLE ELEMENTS` and `allReduce` lets you work on the original graph, with `allReduce` efficiently constraining the larger search space.

Cypher 25 also likely benefits from engine-level optimizations, such as:

*   Dynamic path pruning integrated with `allReduce`
*   Stateful tracking of node visits during traversal
*   Enhanced query planning to prioritize valid paths

These improvements make Cypher 25 a game-changer, reducing coding effort and delivering faster results.

From Hard to Easy: Revisiting Old Assumptions
---------------------------------------------

The leap from 144 seconds to 1.2 seconds in AoC Day 12 shows that what was once hard — or even impossible — with Cypher is now straightforward and fast.

This has big implications for Neo4j customers and developers. In the past, complex graph logic, like constrained path-finding, often required Java stored procedures, which were powerful, but hard to maintain.

Cypher 25’s [`REPEATABLE ELEMENTS`](https://neo4j.com/blog/developer/query-chomp-repeat/) and `allReduce` are two examples of recent graph pattern matching improvements that make it feasible to migrate such procedures to Cypher, resulting in simpler, more maintainable queries.

Summary
-------

Cypher 5 and 25’s new features like `REPEATABLE ELEMENTS` and `allReduce` transform how you tackle complex graph problems, making queries simpler, faster, and more intuitive.

Whether you’re a developer solving puzzles like AoC Day 12 or a business tackling fraud detection, recommendations, or routing, these features empower you to work with your graph’s natural structure, delivering results in seconds, rather than minutes.

A huge kudos to the Neo4j Cypher team for building these powerful tools. Now it’s your turn — go ahead and [set CYPHER 25](https://neo4j.com/docs/cypher-manual/current/queries/select-version/) as your database language default.

Resources
---------

*   [Cypher Versioning](https://neo4j.com/blog/developer/cypher-versioning/)
*   [Neo4j Cypher Query Language](https://neo4j.com/product/cypher-graph-query-language/)
*   [GraphAcademy: Cypher Fundamentals](https://graphacademy.neo4j.com/courses/cypher-fundamentals/?category=beginners)

![Image 4](https://medium.com/_/stat?event=post.clientViewed&referrerSource=full_rss&postId=5a2efb072ba5)

* * *

[Solve Hard Graph Problems With Cypher 25](https://medium.com/neo4j/solve-hard-graph-problems-with-cypher-25-5a2efb072ba5) was originally published in [Neo4j Developer Blog](https://medium.com/neo4j) on Medium, where people are continuing the conversation by highlighting and responding to this story.