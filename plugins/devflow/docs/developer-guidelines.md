# Developer Guidelines

## Code Style

- Don't use `null` for optional values, use `undefined` instead
- Avoid using `any` type, if possible
- Avoid using `as unknown as` type castings, if possible. Consult the user if you need to use it.
- Prefer required parameters over optional, e.g. `param: object | undefined` over `param?: object`. Use optional parameters only when these parameters are not sent in most of the cases.
- Function should have a single return statement. Multiple return statements are an exception for very long functions and initial very short returns, e.g. 1-3 lines at the top to save huge if blocks. Otherwise, use a `let result` variable that you return at the end. For React components, extract conditional content into a variable instead of duplicating the wrapper JSX across multiple returns.
- Use `//` comments, not `/* */` or JSDoc (`/** */`). Keep comments minimal -- only add them where the logic isn't self-evident. Remove verbose documentation comments.
- Avoid `Array.reduce` unless it genuinely shortens the code. Prefer `filter`, `map`, `flatMap`, or a simple `for` loop for clarity.
- When creating utility modules with exposed global functions, prefer wrapping them in a class with static methods rather than loose exported functions. Module-level state (e.g. Reanimated shared values) stays at module level for compatibility, but the public API should go through the class.

```ts
// Module-level state stays here for compatibility
const sharedValue = makeMutable(0);

export class MyUtils {
  static doSomething() { ... }
  static useAnimatedValue() { ... }
}
```

## Naming

- When an object field or interface property is a function, name it with a verb (e.g. `getImporter`, `execTask`), not a bare noun (e.g. `importer`, `task`). This distinguishes callable fields from data fields at a glance.
- The verb should describe what the caller receives, not what the function does internally. For callback/hook fields, name them so they read naturally at the call site: `getPostImportCallback` yields `const postImportCallback = entry.getPostImportCallback()` - clear when later used as `if (postImportCallback) { await postImportCallback(); }`.

## Function Design

- Functions should be small (under 50 lines), perform a single task, and have few parameters (ideally 3 or less)
- Use explicit return types

## Clean Code

- **Code Organization**: Separate concerns (business logic, data access), group related functions, and prefer pure functions without side effects
- **Type Safety**: Use strict typing, avoid `any`, and handle nulls explicitly
- **Code Style**: Adhere to DRY principles, use descriptive naming, extract constants, and comment only complex logic