# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs.

## Quick Start

```bash
# Install dependencies
bundle install

# Basic usage - split by top-level chapters
bundle exec ruby pdf_chapter_splitter.rb input.pdf

# Split at section level (depth 2)
bundle exec ruby pdf_chapter_splitter.rb -d 2 input.pdf

# Preview what will be done (dry-run)
bundle exec ruby pdf_chapter_splitter.rb -n input.pdf

# Force overwrite existing output
bundle exec ruby pdf_chapter_splitter.rb -f input.pdf
```

## Architecture

### Processing Flow

```
Input PDF → [pdf-reader] → Extract Outline → Filter by Depth → Calculate Page Ranges → [hexapdf] → Split PDFs
                ↓
           Chapter Data
           { title:, page:, level:, original_index:, parent_indices: }
```

### Public API (pdf_chapter_splitter.rb)

| Method | Description |
|--------|-------------|
| `initialize` | Parse CLI options and validate input |
| `run` | Main entry point |
| `filter_chapters_by_depth` | Filter chapters by hierarchy level |
| `extract_chapters` | Extract chapter info from PDF outline (memoized) |
| `split_pdf` | Split PDF into individual files |

### Implementation Details

1. **Outline Parsing:**
   - Uses pdf-reader's objects API to access PDF catalog
   - Recursively traverses outline items via First/Next references
   - Handles both direct destinations and action-based destinations

2. **Character Encoding:**
   - Detects and handles UTF-16BE encoded text (common in Japanese PDFs)
   - Removes BOM characters, converts full-width spaces

3. **Depth-Based Splitting:**
   - Depth 1: Top-level chapters only
   - Depth 2+: Includes intermediate levels automatically
   - Chapters without children at target depth are included as complete chapters

## Testing

```bash
# REQUIRED: Generate test PDFs first (one-time setup)
bundle exec ruby spec/support/generate_test_pdfs.rb

# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/pdf_chapter_splitter_spec.rb:42

# Documentation format
bundle exec rspec -fd
```

## Code Quality

```bash
# Run linter
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Auto-fix with unsafe corrections
bundle exec rubocop -A
```

## Implementation Guidelines

When modifying this codebase:

1. **Single-file architecture**: All logic stays in `pdf_chapter_splitter.rb`
2. **Public API stability**: Do not change signatures of public methods (initialize, run, extract_chapters, filter_chapters_by_depth, split_pdf)
3. **Error handling**: Catch specific error types, use `error_exit` for consistent error output
4. **Chapter data structure**: Always include `{ title:, page:, level:, original_index: }`
5. **Test coverage**: Add tests for new functionality, test public API only

## Known Issues

1. **Prawn Circular Dependency Warning**: Appears during test runs due to Prawn 2.5.0 internal issue. On Ruby 4.0+, this warning causes rspec to exit with code 1 even when all tests pass. Safe to ignore.

2. **HexaPDF License**: Uses AGPL-3.0. Commercial users should consider HexaPDF's commercial license.

3. **Appendix Detection**: Simplified - assumes all pages after last chapter are appendix.

4. **Named Destinations**: Complex named destinations may not resolve correctly in PDFs without a Names dictionary. PDFs with a Names dictionary resolve correctly.

## Debug Commands

```bash
# View PDF outline structure
bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').outline"

# Count total pages
bundle exec ruby -r pdf-reader -e "puts PDF::Reader.new('file.pdf').page_count"
```
