# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PDF Chapter Splitter is a Ruby script designed to automatically detect chapter boundaries in PDF files and split them into individual chapter PDFs. The project is currently in its initial setup phase with no implementation yet.

## Project Status

This is a newly initialized Ruby project with:
- Basic README describing intended functionality
- MIT License
- Ruby-specific .gitignore file
- No implementation code exists yet

## Development Setup

Since this is a new project, the following setup will be needed when implementing:

### Ruby Version
- Create a `.ruby-version` file to specify the Ruby version
- Add `ruby File.read('.ruby-version').strip` to the Gemfile

### Dependencies
When implementing the PDF splitting functionality, you'll likely need:
- A PDF manipulation gem (e.g., `pdf-reader`, `hexapdf`, or `combine_pdf`)
- Create a `Gemfile` with required dependencies
- Run `bundle install` after creating the Gemfile

### Project Structure (Suggested)
```
├── lib/
│   └── pdf_chapter_splitter.rb  # Main implementation
├── spec/
│   └── pdf_chapter_splitter_spec.rb  # RSpec tests
├── bin/
│   └── pdf-chapter-splitter  # Executable script
├── Gemfile
├── .ruby-version
├── .rubocop.yml  # Ruby linter configuration
└── Rakefile  # Build tasks
```

## Common Commands

Once the project is set up:

```bash
# Install dependencies
bundle install

# Run tests (after adding RSpec)
bundle exec rspec
bundle exec rspec spec/pdf_chapter_splitter_spec.rb  # Specific file
bundle exec rspec spec/pdf_chapter_splitter_spec.rb:42  # Specific line

# Run linter (after adding RuboCop)
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues

# Run the script (after implementation)
ruby bin/pdf-chapter-splitter input.pdf
# or if made executable:
./bin/pdf-chapter-splitter input.pdf
```

## Implementation Notes

The script should:
1. Accept a PDF file path as input
2. Analyze the PDF to detect chapter boundaries (possibly by looking for specific patterns like "Chapter N" or significant formatting changes)
3. Split the PDF into individual files, one per chapter
4. Save the chapter PDFs with meaningful names (e.g., `chapter_1.pdf`, `chapter_2.pdf`)

## Testing Approach

- Use RSpec for testing
- Create sample PDF fixtures for testing
- Test edge cases like PDFs without clear chapter markers
- Ensure proper error handling for invalid inputs