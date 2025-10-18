# giblish Development Guide

## 0. Project Structure

This repo contains two projects written in ruby. The main application `giblish` and a gem `gran` which is also consumed by `giblish`.

This file (CLAUDE.md) is in the top level of the repo. Some notable directories are shown in this example:

```bash
<repo-root>
├── CLAUDE.md  # this file
├── giblish    # top dir for the main application
│   ├── bin    # contains setup scripts
│   ├── docs   # contains all reference documentation
│   ├── lib    # top dir for the giblish source code
│   ├── test   # top dir for the automated tests
│   └── web_apps # top dir for helper applications that add functionality
└── gran       # top dir for the `gran` gem
```

## 0.5 General coding rules

* **ALWAYS** ask the human when a task or scope is unclear.
* **NEVER**  make assumptions when the alternative is to ask the user.
* **ALWAYS** Add/update **`AIDEV-NOTE:` anchor comments** near non-trivial edited code.
* **ALWAYS** Run linting using `bundle exec rake standard` after an update to verify that updated/added code complies with the project's formatting rules.
* **NEVER** finish a task involving code updates without verifying a clean linting run.

## 1. Setup and Installation

The projects use `rbenv` to manage ruby versions.

```bash
# setup the project for the first time
cd <repo-root>/giblish
bin/setup

# run the built application
bundle exec giblish
```

## 2. Build and Package

```bash
# TBD
```

## 3. Development Workflow

### 3.1 Code Style and Formatting

We follow strict coding standards to ensure consistency across the codebase:

- **Imports**:
  - Order: Standard library → Third party → Project modules
  - All imports alphabetically sorted within each group

- **Naming Conventions**:
  - Classes: `PascalCase`
  - Functions/Variables: `snake_case`
  - Constants: `UPPER_CASE`

- **Order of methods within a class**:

From top to bottom:
  - attr_reader
  - attr_writer
  - attr_accessor
  - static methods
  - class methods
  - the `initialize` method
  - public instance methods
  - protected instance methods
  - private instance methods

- **Documentation**:
  - YARD is used to document classes and methods
  - Document all public classes and methods, include the types of arguments for methods
  - **ALWAYS** use correct type hints for method parameters and return values when updating/adding code
  - solargraph is used to provide IDE integration with regards to intellisense, jump-to-types etc

### 3.2 Coding patterns and guidelines

 * **PREFER** Low-complexity code. If there is a choice, prefer to reduce the code complexity and code size.
 * **ALWAYS** Follow established patterns. There are many patterns already in the code base. Look through the code base for existing patterns before starting to implement a new one.
 * **NEVER** Keep backward compatibility. The code base is in flux and we use git. Remove unused or stale code and patterns instead of trying to be backward compatible. This applies to comments as well as code. Do not refer to old or removed code or patterns in comments. Example comments to avoid:
  a. "Replaced the hard-coded value with a provider pattern"
  b. "Moved method X to class Y"

### 3.3 Anchor comments

Add/read specially formatted comments when appropriate as outlined below.

**Guidelines**

- Use `AIDEV-NOTE:`, `AIDEV-TODO:`, or `AIDEV-QUESTION:` (all-caps prefix) for comments aimed at AI and developers.
- Keep them concise (≤ 120 chars).
- **ALWAYS** try to locate existing `AIDEV-*` in relevant files when starting to solve a task
- **ALWAYS** Update relevant anchors when modifying associated code.
- **NEVER** Include language that refer to how code looked before.
Example on **DO NOT**:
```python
  # AIDEV-NOTE: previously the class was named OldClass
  # AIDEV-NOTE: the code now make use of dependency injection
```

Example on **DO**:
```python
# AIDEV-NOTE: perf-hot-path; avoid extra allocations (see ADR-24)
# AIDEV-NOTE: this is complex due to how caching is implemented
# AIDEV-TODO: this class should be renamed to comply with the domain concepts
```

### 3.4 Code Quality Tools

```bash
# Format and lint code
bundle exec rake standard
```

## 4. Testing

These projects use the Minitest framework for automated tests.

### 4.1 Running Tests

```bash
# Run all tests:
bundle exec rake all
# Run specific test:
bundle exec ruby -Ilib:test test/path/to/test_file.rb
```

### 4.2 Testing Guidelines

 * **ALWAYS** Follow the existing file structure. Test files shall be organized in folders mirroring the source code folders. EXAMPLE:
```bash
# code in source file
giblish/lib/giblish/docid/docid.rb
# should be tested by tests in
giblish/test/docid/docid_test.rb
```

 * **ALWAYS** Test _ONLY_ the public API of a class or method.
 * **NEVER** Test internal implementation details that require mocking to be accessed.
 * **PREFER** To focus tests on Behavior not implementation details.
 * **PREFER** To use Callbacks and Observables in favour of inspecting internal variables.
 * **PREFER** To create Fixtures for reusable test components where appropriate.

## 5. Git Workflow

### 5.1 Commit Guidelines

* **NEVER** include references to claude in commit messages. Do _not_ add any mentions of claude in commit messages, author ro co-author fields. EXAMPLE of string to _exclude_:
   Co-Authored-By: Claude <noreply@anthropic.com>"
- **Keep commit messages concise and descriptive**

### 5.2 Versioning

- Git tags follow the format: `race-<major>.<minor>.<patch>`

## 6. CI/CD

TBD
