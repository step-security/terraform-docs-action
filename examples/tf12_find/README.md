# Test Find

## Input

```yaml
- name: Should generate USAGE.md for tf12_find and its submodules
  uses: ./
  with:
    find-dir: examples/tf12_find
    output-file: USAGE.md
```

## Verify

- Should replace USAGE.md in `examples/tf12_find` and `examples/tf12_find/modules/tf12_find_submodules`

## Usage

See USAGE.md
