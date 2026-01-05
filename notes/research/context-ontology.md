Nice, this is right in your sweet spot 😄
Let’s design a **fact-store memory model** where:

* **OWL** = schema for what a “fact” / “memory” is
* **SHACL** = guardrails to keep facts clean, consistent, and “context-friendly” for LLM use

I’ll keep it practical for implementation later (Elixir + RDF.ex + SHACL engine).

---

## 1. Goals of the fact-store memory model

We want a memory system that:

1. Stores **facts, not chat logs**
2. Is **context-aware** (session, task, turn, global)
3. Tracks **provenance, confidence, and recency**
4. Enforces structure with **SHACL** so junk doesn’t leak into prompts
5. Plays nicely with **LLM retrieval** (SPARQL + filters for relevance)

So the model will revolve around:

* **Facts / Claims**
* **Entities** (what the facts are about)
* **Context scopes** (global, session, task, turn)
* **Provenance & evidence**
* **Scoring & status** (confidence, salience, validity)

---

## 2. High-level ontology modules

You can keep this modular:

1. `jido-memory-core.owl` – basic concepts: Fact, Context, Source, Agent
2. `jido-memory-fact-types.owl` – fact categories (preference, goal, constraint, etc.)
3. `jido-memory-provenance.owl` – links to PROV-O / your existing ontologies
4. `jido-memory-shapes.ttl` – SHACL shapes validating the above

Below I’ll focus on the core model.

---

## 3. Core OWL classes

### 3.1. Facts & Claims

```text
jmem:Fact              – atomic “rememberable” unit
jmem:Claim             – a proposition, usually natural-language or normalized
jmem:DerivedFact       – a fact inferred from other facts
jmem:PlanStepFact      – fact representing a step in a plan
jmem:UserPreference    – fact about user preferences
jmem:ConstraintFact    – fact expressing a constraint / rule
jmem:ToolResultFact    – fact summarizing a tool call result
```

All of these are subclasses of `jmem:Fact`.

**Key idea**: the LLM doesn’t see raw conversation; it sees **selected jmem:Fact instances**, serialized as structured text.

---

### 3.2. Entities & Context

Use your existing Elixir / Jido / Project ontologies where possible. At the memory level:

```text
jmem:Entity            – anything a fact can be “about”
jmem:MemoryContext     – a scope in which facts are valid/relevant

Subclasses of jmem:MemoryContext:
  jmem:GlobalContext       – long-term “always true” facts
  jmem:SessionContext      – per chat session / working session
  jmem:TaskContext         – per task/goal (e.g., “Implement SHACL reader”)
  jmem:TurnContext         – ultra-local facts for a single interaction
```

You’d connect this to your **agent / work-session / project** ontologies:

```text
jmem:SessionContext  rdfs:subClassOf  jido:WorkSession .
jmem:TaskContext     rdfs:subClassOf  jido:Task .
```

---

### 3.3. Provenance & Source

```text
jmem:Source           – where the fact came from (doc, tool, user utterance)
jmem:UserUtterance    – fact extracted from user message
jmem:ToolInvocation   – fact derived from a tool result
jmem:DocumentSource   – fact extracted from a doc / repo / page
jmem:AgentInference   – fact derived by an agent (LLM reasoning, planner, etc.)
```

You can align these with **PROV-O**:

```text
jmem:Source       rdfs:subClassOf  prov:Entity .
jmem:AgentInference rdfs:subClassOf prov:Activity .
```

---

## 4. Core OWL object & data properties

### 4.1. Object properties

```text
jmem:aboutEntity        – Fact → Entity
jmem:inContext          – Fact → MemoryContext
jmem:hasSource          – Fact → Source
jmem:supportedBy        – Fact → Fact (evidence chain)
jmem:contradictedBy     – Fact → Fact
jmem:derivedFrom        – DerivedFact → Fact
```

These let you:

* model **what** the fact is about
* **where** it applies (context scope)
* **why** we believe it (source/evidence)
* how conflicts are tracked (contradictions)

---

### 4.2. Data properties

```text
jmem:statementText      – xsd:string   (natural language form)
jmem:normalizedForm     – xsd:string   (canonical representation, optional)
jmem:confidence         – xsd:decimal  (0.0–1.0)
jmem:salience           – xsd:decimal  (0.0–1.0; “importance for context”)
jmem:createdAt          – xsd:dateTime
jmem:updatedAt          – xsd:dateTime
jmem:validFrom          – xsd:dateTime
jmem:validUntil         – xsd:dateTime
jmem:status             – xsd:string   (e.g., “active”, “superseded”, “rejected”)
jmem:language           – xsd:language (optional)
```

These will be super useful in SPARQL queries when deciding what to push into the prompt.

---

## 5. Example: a single fact in Turtle

```turtle
@prefix jmem: <http://example.org/jido/memory#> .
@prefix ex:   <http://example.org/project#> .
@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .

ex:session-123 a jmem:SessionContext ;
  rdfs:label "JidoCode work-session for SHACL design" .

ex:user-1 a jmem:Entity ;
  rdfs:label "Pascal Charbonneau" .

ex:fact-001 a jmem:UserPreference ;
  jmem:aboutEntity ex:user-1 ;
  jmem:inContext ex:session-123 ;
  jmem:hasSource ex:utterance-456 ;
  jmem:statementText "User prefers Elixir-based tooling and OWL ontologies for memory." ;
  jmem:confidence "0.95"^^xsd:decimal ;
  jmem:salience "0.9"^^xsd:decimal ;
  jmem:createdAt "2026-01-05T12:10:00"^^xsd:dateTime ;
  jmem:status "active" .

ex:utterance-456 a jmem:UserUtterance ;
  rdfs:label "User message from 2026-01-05T12:09:59" .
```

---

## 6. SHACL: keep facts clean & usable

Now we wrap this in SHACL so your pipeline **refuses garbage** and enforces a consistent structure.

### 6.1. Shape for any `jmem:Fact`

```turtle
@prefix sh:   <http://www.w3.org/ns/shacl#> .
@prefix jmem: <http://example.org/jido/memory#> .
@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .

jmem:FactShape
  a sh:NodeShape ;
  sh:targetClass jmem:Fact ;

  # Every fact must have statementText
  sh:property [
    sh:path jmem:statementText ;
    sh:datatype xsd:string ;
    sh:minCount 1 ;
  ] ;

  # Must be about at least one entity
  sh:property [
    sh:path jmem:aboutEntity ;
    sh:minCount 1 ;
  ] ;

  # Must have a context
  sh:property [
    sh:path jmem:inContext ;
    sh:minCount 1 ;
  ] ;

  # Optional but constrained numeric confidence
  sh:property [
    sh:path jmem:confidence ;
    sh:datatype xsd:decimal ;
    sh:minInclusive 0.0 ;
    sh:maxInclusive 1.0 ;
    sh:maxCount 1 ;
  ] ;

  # Optional salience, same constraints
  sh:property [
    sh:path jmem:salience ;
    sh:datatype xsd:decimal ;
    sh:minInclusive 0.0 ;
    sh:maxInclusive 1.0 ;
    sh:maxCount 1 ;
  ] ;

  # Status must come from a small vocabulary
  sh:property [
    sh:path jmem:status ;
    sh:in ( "active" "superseded" "rejected" "candidate" ) ;
    sh:maxCount 1 ;
  ] .
```

### 6.2. Shape for “unique per entity per context” facts

For some fact types (e.g. **current preference**, **current goal**), you don’t want duplicates:

```turtle
jmem:UserPreferenceShape
  a sh:NodeShape ;
  sh:targetClass jmem:UserPreference ;

  sh:property [
    # Keys: (aboutEntity, inContext, normalizedForm)
    sh:path ( jmem:aboutEntity jmem:inContext jmem:normalizedForm ) ;
    sh:uniqueLang false ;   # we want uniqueness, not per-language uniqueness
    # In practice you'd use sh:uniqueComponents in SHACL-SPARQL,
    # or enforce uniqueness at the application level.
  ] .
```

In practice you’ll probably implement “no duplicates” with **application logic + a SHACL-SPARQL constraint** that checks for existing facts with the same key.

---

## 7. How this supports “clear, structured context”

### 7.1. LLM-facing retrieval

When building the prompt for the next turn, you can run SPARQL like:

* **Get active, salient session-level facts**

```sparql
SELECT ?fact ?text ?salience ?confidence WHERE {
  ?fact a jmem:Fact ;
        jmem:inContext ex:session-123 ;
        jmem:status "active" ;
        jmem:statementText ?text ;
        jmem:salience ?salience .
  OPTIONAL { ?fact jmem:confidence ?confidence . }
}
ORDER BY DESC(?salience) DESC(?confidence)
LIMIT 30
```

* **Get global user preferences**

* **Get current task’s constraints and goals**

Then serialize them like:

```text
[User Preferences]
- User prefers Elixir and Ash-based tooling.
- User often uses OWL + SHACL for schema validation.

[Task Context]
- Implement a fact-store memory using OWL/SHACL for Jido/JidoAi.
...
```

This is **clean, logically ordered context** – no chatter.

---

### 7.2. Ingestion and consolidation pipeline

A typical loop:

1. **After a turn**:

   * Extract candidate facts from the conversation + tool results (LLM or custom pipeline).
   * Normalize them (canonical wording, entity linking).

2. **Validate with SHACL**:

   * Reject malformed facts.
   * Ensure required properties exist.

3. **Check for duplicates / conflicts**:

   * If same `(aboutEntity, inContext, normalizedForm)` exists:

     * Update timestamps, salience, confidence
   * If conflicting (e.g., “X prefers Python” vs “X prefers Elixir”):

     * Mark old fact `superseded`, link new fact with `contradictedBy`

4. **Update salience**:

   * Every time a fact is used or referenced, bump its salience.
   * Apply time-decay for unused facts.

5. **On retrieval**:

   * Pull highest-salience + relevant-context facts into the LLM prompt.

---

## 8. Context layers in the model

You can enforce a discipline like:

* **GlobalContext**: user identity, long-term preferences, capabilities
* **SessionContext**: current project, high-level goal, environment details
* **TaskContext**: problem we’re solving right now, constraints, plan
* **TurnContext**: immediate intermediate results (tool output summaries, etc.)

In OWL:

```turtle
jmem:GlobalContext   rdfs:subClassOf jmem:MemoryContext .
jmem:SessionContext  rdfs:subClassOf jmem:MemoryContext .
jmem:TaskContext     rdfs:subClassOf jmem:MemoryContext .
jmem:TurnContext     rdfs:subClassOf jmem:MemoryContext .
```

Then SHACL shape to ensure each context is typed and described:

```turtle
jmem:MemoryContextShape
  a sh:NodeShape ;
  sh:targetClass jmem:MemoryContext ;
  sh:property [
    sh:path rdfs:label ;
    sh:minCount 1 ;
  ] ;
  sh:property [
    sh:path jmem:createdAt ;
    sh:datatype xsd:dateTime ;
    sh:minCount 1 ;
  ] .
```

---

## 9. How this plugs into your ecosystem

This model is a good fit for:

* **Elixir + RDF.ex**: you can model `jmem:` vocabulary directly.
* **Your Elixir ontology**: `jmem:Entity` can reference `elixir:Module`, `elixir:Function`, etc.
* **Jido / JidoAi**:

  * each agent / work-session maps to a `jmem:SessionContext`
  * planner agent writes `PlanStepFact`
  * memory writer agent maintains `jmem:Fact` + SHACL validation
  * memory reader agent runs SPARQL to assemble context blocks

---

If you’d like next, I can:

* sketch a **Jido MemoryWriter / MemoryReader API** that reads/writes these facts, or
* define a **concrete `jido-memory-core.ttl` file** you can drop into your `elixir-ontologies` / `onto_view` repos.

