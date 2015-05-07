
# -*- coding: utf-8 -*-

module RobustExcelOle

  class BookStore

    def initialize
      @filename2books = Hash.new {|hash, key| hash[key] = [] }
    end

    # returns a book with the given filename, if it was open once
    # prefers open books to closed books, and among them, prefers more recently opened books
    # options: :prefer_writable   return the writable book, if it is open (default: true)
    #                             return the book according to the preference order mentioned above, otherwise
    #          :prefer_excel      return the book in the given excel instance, if it exists
    #                             proceed according to prefer_writable otherwise
    def fetch(filename, options = { })
      filename_key = RobustExcelOle::canonize(filename)
      weakref_books = @filename2books[filename_key]
      return nil unless weakref_books
      result = readonly_book = readonly_unsaved_book = closed_book = nil      
      weakref_books.each do |wr_book|
        if (not wr_book.weakref_alive?)
          @filename2books[filename_key].delete(wr_book)
        else
          if options[:prefer_excel] && wr_book.excel == options[:prefer_excel]
            result = wr_book
            break 
          end
          if wr_book.alive?
            if (not wr_book.readonly)
              result = wr_book
              break if options[:prefer_writable]
            else
              wr_book.saved ? readonly_book = wr_book : readonly_unsaved_book = wr_book
            end
          else
            closed_book = wr_book
          end
        end
      end
      result = result ? result : (readonly_unsaved_book ? readonly_unsaved_book : (readonly_book ? readonly_book : closed_book))
      result.__getobj__ if result
    end

    # stores a book
    def store(book)
      filename_key = RobustExcelOle::canonize(book.filename)      
      if book.stored_filename
        old_filename_key = RobustExcelOle::canonize(book.stored_filename)
        # deletes the weak reference to the book
        @filename2books[old_filename_key].delete(book)
      end
      @filename2books[filename_key] |= [WeakRef.new(book)]
      book.stored_filename = book.filename
    end

    # returns all excel instances and the workbooks that are open in them
    # first: only the stored excel instances are considered
    def excel_list
      excel2books = Hash.new {|hash, key| hash[key] = [] }
      if @filename2books
        @filename2books.each do |filename,books|
          if books
            books.each do |book|
              excel2books[book.excel] |= [book.workbook]
            end
          end
        end
      end
      excel2books
    end

    # prints the book store
    def print
      p "@filename2books:"
      if @filename2books
        @filename2books.each do |filename,books|
          p " filename: #{filename}"
          p " books:"
          p " []" if books == []
          if books
            books.each do |book|
              if book.weakref_alive?
                p "#{book}"
                p "excel: #{book.excel}"
                p "alive: #{book.alive?}"
              else
                p "weakref not alive"
              end
            end
          end
        end
      end
    end

  end

  class BookStoreError < WIN32OLERuntimeError
  end
 
end
