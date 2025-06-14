# frozen_string_literal: true

require "prawn"
require "hexapdf"

module TestPDFGenerator
  module_function

  def generate_all
    generate_pdf_with_outline
    generate_pdf_without_outline
    generate_japanese_pdf_with_outline
    generate_pdf_with_complex_outline
  end

  def generate_pdf_with_outline
    filename = File.join(__dir__, "../fixtures/sample_with_outline.pdf")

    # First create a basic PDF with Prawn
    Prawn::Document.generate(filename) do |pdf|
      # Front matter
      pdf.text "Title Page", size: 24, align: :center
      pdf.move_down 20
      pdf.text "This is the title page"
      pdf.start_new_page

      pdf.text "Table of Contents", size: 20
      pdf.move_down 10
      pdf.text "Chapter 1: Introduction ... 3"
      pdf.text "Chapter 2: Getting Started ... 5"
      pdf.text "Chapter 3: Advanced Topics ... 7"
      pdf.start_new_page

      # Chapter 1
      pdf.text "Chapter 1: Introduction", size: 18
      pdf.move_down 10
      pdf.text "This is the introduction chapter."
      pdf.start_new_page
      pdf.text "Introduction continued..."
      pdf.start_new_page

      # Chapter 2
      pdf.text "Chapter 2: Getting Started", size: 18
      pdf.move_down 10
      pdf.text "This chapter covers getting started."
      pdf.start_new_page
      pdf.text "Getting started continued..."
      pdf.start_new_page

      # Chapter 3
      pdf.text "Chapter 3: Advanced Topics", size: 18
      pdf.move_down 10
      pdf.text "This chapter covers advanced topics."
      pdf.start_new_page

      # Appendix
      pdf.text "Appendix A: Reference", size: 16
      pdf.move_down 10
      pdf.text "Reference material goes here."
    end

    # Now add outline using HexaPDF
    doc = HexaPDF::Document.open(filename)

    # Create outline
    doc.catalog[:Outlines] = doc.add({
                                       Type: :Outlines,
                                       Count: 3
                                     })

    # Chapter 1
    ch1 = doc.add({
                    Title: "Chapter 1: Introduction",
                    Parent: doc.catalog[:Outlines],
                    Dest: [doc.pages[2], :Fit]
                  })

    # Chapter 2
    ch2 = doc.add({
                    Title: "Chapter 2: Getting Started",
                    Parent: doc.catalog[:Outlines],
                    Prev: ch1,
                    Dest: [doc.pages[4], :Fit]
                  })
    ch1[:Next] = ch2

    # Chapter 3
    ch3 = doc.add({
                    Title: "Chapter 3: Advanced Topics",
                    Parent: doc.catalog[:Outlines],
                    Prev: ch2,
                    Dest: [doc.pages[6], :Fit]
                  })
    ch2[:Next] = ch3

    # Set first and last
    doc.catalog[:Outlines][:First] = ch1
    doc.catalog[:Outlines][:Last] = ch3

    doc.write(filename, optimize: true)
  end

  def generate_pdf_without_outline
    filename = File.join(__dir__, "../fixtures/sample_without_outline.pdf")

    Prawn::Document.generate(filename) do |pdf|
      pdf.text "Document Without Outline", size: 24, align: :center
      pdf.move_down 20
      pdf.text "This PDF has no outline/bookmarks."
      pdf.start_new_page

      pdf.text "Page 2", size: 18
      pdf.text "Content on page 2"
      pdf.start_new_page

      pdf.text "Page 3", size: 18
      pdf.text "Content on page 3"
    end
  end

  def generate_japanese_pdf_with_outline
    filename = File.join(__dir__, "../fixtures/japanese_with_outline.pdf")

    # Create PDF with Prawn (using default font for now)
    Prawn::Document.generate(filename) do |pdf|
      # Use Helvetica for ASCII text
      pdf.text "Japanese Document", size: 24, align: :center
      pdf.move_down 20
      pdf.text "This document has Japanese chapter titles"
      pdf.start_new_page

      pdf.text "Chapter 1", size: 18
      pdf.text "First chapter content"
      pdf.start_new_page

      pdf.text "Chapter 2", size: 18
      pdf.text "Second chapter content"
      pdf.start_new_page

      pdf.text "Chapter 3", size: 18
      pdf.text "Third chapter content"
    end

    # Add Japanese outline using HexaPDF
    doc = HexaPDF::Document.open(filename)

    # Create outline
    doc.catalog[:Outlines] = doc.add({
                                       Type: :Outlines,
                                       Count: 3
                                     })

    # Japanese chapter titles (UTF-16BE encoded for PDF)
    titles = [
      "第1章　はじめに",
      "第2章　基本編",
      "第3章　応用編"
    ]

    # Create outline items
    prev_item = nil
    first_item = nil

    titles.each_with_index do |title, index|
      # Convert to UTF-16BE with BOM for PDF
      bom = "\xFE\xFF".dup.force_encoding("BINARY")
      title_utf16 = title.encode("UTF-16BE", "UTF-8").force_encoding("BINARY")
      pdf_title = bom + title_utf16

      item = doc.add({
                       Title: pdf_title,
                       Parent: doc.catalog[:Outlines],
                       Dest: [doc.pages[index + 1], :Fit]
                     })

      if prev_item
        item[:Prev] = prev_item
        prev_item[:Next] = item
      else
        first_item = item
      end

      prev_item = item
    end

    doc.catalog[:Outlines][:First] = first_item
    doc.catalog[:Outlines][:Last] = prev_item

    doc.write(filename, optimize: true)
  end

  def generate_pdf_with_complex_outline
    filename = File.join(__dir__, "../fixtures/complex_outline.pdf")

    Prawn::Document.generate(filename) do |pdf|
      pdf.text "Complex Document", size: 24, align: :center
      pdf.start_new_page

      # Multiple chapters with nested sections
      5.times do |i|
        pdf.text "Chapter #{i + 1}", size: 18
        pdf.text "Chapter #{i + 1} content"
        pdf.start_new_page

        # Add some pages for each chapter
        2.times do |j|
          pdf.text "Section #{i + 1}.#{j + 1}", size: 16
          pdf.text "Section content"
          pdf.start_new_page if i < 4 || j < 1
        end
      end
    end

    # Add complex outline with nested items
    doc = HexaPDF::Document.open(filename)

    doc.catalog[:Outlines] = doc.add({
                                       Type: :Outlines,
                                       Count: 5
                                     })

    # Create chapters with nested sections
    prev_chapter = nil
    first_chapter = nil
    page_num = 1

    5.times do |i|
      chapter = doc.add({
                          Title: "Chapter #{i + 1}: Topic #{i + 1}",
                          Parent: doc.catalog[:Outlines],
                          Dest: [doc.pages[page_num], :Fit],
                          Count: 2
                        })

      page_num += 1

      # Add sections
      prev_section = nil
      first_section = nil

      2.times do |j|
        section = doc.add({
                            Title: "Section #{i + 1}.#{j + 1}",
                            Parent: chapter,
                            Dest: [doc.pages[page_num], :Fit]
                          })

        if prev_section
          section[:Prev] = prev_section
          prev_section[:Next] = section
        else
          first_section = section
        end

        prev_section = section
        page_num += 1
      end

      chapter[:First] = first_section
      chapter[:Last] = prev_section

      if prev_chapter
        chapter[:Prev] = prev_chapter
        prev_chapter[:Next] = chapter
      else
        first_chapter = chapter
      end

      prev_chapter = chapter
    end

    doc.catalog[:Outlines][:First] = first_chapter
    doc.catalog[:Outlines][:Last] = prev_chapter

    doc.write(filename, optimize: true)
  end
end

# Generate test PDFs if run directly
if __FILE__ == $PROGRAM_NAME
  TestPDFGenerator.generate_all
  puts "Test PDFs generated in spec/fixtures/"
end
