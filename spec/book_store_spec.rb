# -*- coding: utf-8 -*-

require File.join(File.dirname(__FILE__), './spec_helper')

RSpec.configure do |config|

  config.mock_with :rspec do |mocks|
    mocks.syntax = :should
  end
end


$VERBOSE = nil

include RobustExcelOle
module RobustExcelOle
  class MockBookstore
    def fetch(filename, options = { })
      nil
    end
    def store(book)
    end
    def print
      puts "MockBookstore is always empty"
    end
  end
end


$mock_bookstore = MockBookstore.new

class Book
  @@bookstore = $mock_bookstore
end


describe BookStore do

  before(:all) do
    excel = Excel.new(:reuse => true)
    open_books = excel == nil ? 0 : excel.Workbooks.Count
    puts "*** open books *** : #{open_books}" if open_books > 0
    Excel.close_all
  end

  before do
    @bookstore = BookStore.new
    @dir = create_tmpdir
    @simple_file = @dir + '/simple.xls'
    @simple_save_file = @dir + '/simple_save.xls'
    @different_file = @dir + '/different_simple.xls'
    @simple_file_other_path = @dir + '/more_data/simple.xls'
  end

  after do
    Excel.close_all
    rm_tmp(@dir)
  end

  describe "create bookstore" do
    context "with standard" do
      it "should create book store" do
        expect {
          @book_store = BookStore.new
        }.to_not raise_error
        @book_store.should be_a BookStore
      end
    end
  end

  describe "Mock-Test" do
    it "should never store any book" do
      b1 = Book.open(@simple_file)
      b2 = Book.open(@simple_file)
      b2.object_id.should_not == b1.object_id
    end
  end


  describe "fetch" do
    
    context "with one open book" do
      
      before do
        @book = Book.open(@simple_file)
      end

      after do
        @book.close
      end

      it "should do simple store and fetch" do        
        @bookstore.store(@book)
        new_book = @bookstore.fetch(@simple_file)
        new_book.should be_a Book
        new_book.should be_alive
        new_book.should == @book
        new_book.close
      end

      it "should fetch one book several times" do        
        @bookstore.store(@book)
        book1 = @bookstore.fetch(@simple_file)
        book2 = @bookstore.fetch(@simple_file)
        expect(book1).to be_a Book
        book1.should be_alive
        book1.should == @book
        book2.should be_a Book
        book2.should be_alive
        book2.should == @book
        book1.should == book2
        book1.close
        book2.close
      end

      it "should fetch nothing without stóring before" do
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == nil
      end

      it "should fetch nothing when fetching a different book" do
        @bookstore.store(@book)
        new_book = @bookstore.fetch(@different_file)
        new_book.should == nil
      end

      it "should fetch nothing when fetching a non-existing book" do
        @bookstore.store(@book)
        new_book = @bookstore.fetch("foo")
        new_book.should == nil
      end

    end

    context "with several books" do

      before do
        @book = Book.open(@simple_file)
        @bookstore.store(@book)
      end

      after do
        @book.close
        @book2.close(:if_unsaved => :forget)
      end

      it "should store and open two different books" do
        @book2 = Book.open(@different_file)
        @bookstore.store(@book2)
        new_book = @bookstore.fetch(@simple_file)
        new_book2 = @bookstore.fetch(@different_file)
        new_book.should be_a Book
        new_book.should be_alive
        new_book.should == @book
        new_book2.should be_a Book
        new_book2.should be_alive
        new_book2.should == @book2
        new_book.should_not == new_book2
        new_book.close
        new_book2.close
      end

      it "should fetch the first, writable book" do
        @book2 = Book.open(@simple_file, :force_excel => :new)
        @bookstore.store(@book2)
        @book.ReadOnly.should be_false
        @book2.ReadOnly.should be_true
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book
        new_book.should_not == @book2
        new_book.close
      end

      it "should fetch the writable book even if the readonly book has unsaved changes" do
        @book2 = Book.open(@simple_file, :force_excel => :new)
        sheet = @book2[0]
        @bookstore.store(@book2)
        sheet[0,0] = sheet[0,0].value == "simple" ? "complex" : "simple"
        @book.ReadOnly.should be_false
        @book2.ReadOnly.should be_true
        @book2.Saved. should be_false
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book
        new_book.should_not == @book2
        new_book.close
      end

    end

    context "with readonly book" do

      before do
        @book = Book.open(@simple_file, :read_only => true)
        @bookstore.store(@book)
      end

      after do
        @book.close
        @book2.close(:if_unsaved => :forget)
      end

      it "should fetch the second, writable book" do
        @book2 = Book.open(@simple_file, :force_excel => :new)
        @bookstore.store(@book2)
        @book.ReadOnly.should be_true
        @book2.ReadOnly.should be_false
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book2
        new_book.should_not == @book
        new_book.close
      end

      it "should fetch the recent readonly book when there are only readonly books" do
        @book2 = Book.open(@simple_file, :force_excel => :new, :read_only => true)
        @bookstore.store(@book2)
        @book.ReadOnly.should be_true
        @book2.ReadOnly.should be_true
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book2
        new_book.should_not == @book
        new_book.close
      end

      it "should fetch the second readonly book with unsaved changes" do
        @book2 = Book.open(@simple_file, :force_excel => :new, :read_only => true)
        sheet = @book2[0]
        @bookstore.store(@book2)
        sheet[0,0] = sheet[0,0].value == "simple" ? "complex" : "simple"
        @book.ReadOnly.should be_true
        @book2.ReadOnly.should be_true
        @book2.Saved.should be_false
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book2
        new_book.should_not == @book        
        new_book.close
      end

      it "should fetch the second, writable book, if a writable, a readonly and an unsaved readonly book exist" do
        @book2 = Book.open(@simple_file, :force_excel => :new)
        @book3 = Book.open(@simple_file, :force_excel => :new)
        @bookstore.store(@book2)
        @bookstore.store(@book3)
        sheet = @book3[0]
        sheet[0,0] = sheet[0,0].value == "simple" ? "complex" : "simple"
        @book.ReadOnly.should be_true
        @book2.ReadOnly.should be_false
        @book3.ReadOnly.should be_true
        @book3.Saved.should be_false
        new_book = @bookstore.fetch(@simple_file)
        new_book.should == @book2
        new_book.should_not == @book        
        new_book.should_not == @book3  
        new_book.close
      end
    end
   
    context "with changing file name" do

      before do
        @book = Book.open(@simple_file)
        @book.save_as(@simple_save_file, :if_exists => :overwrite)      
        @bookstore = @book.book_store
      end

      after do
        @book.close
      end

      it "should return only book with correct file name" do
        book1 = @bookstore.fetch(@simple_save_file)
        book1.should == @book
      end

      it "should return only book with correct file name" do
        book1 = @bookstore.fetch(@simple_file)
        book1.should == nil
      end
    end

    context "with given excel instance and fetching readonly" do
      
      before do
        @book = Book.open(@simple_file)
        @bookstore.store(@book)
        @book2 = Book.open(@simple_file, :force_excel => :new)
        @bookstore.store(@book2)        
      end

      after do
        @book.close
      end

      it "should fetch the book in the given excel instance" do
        @book.ReadOnly.should be_false
        @book2.ReadOnly.should be_true
        book_new = @bookstore.fetch(@simple_file, :excel => @book2.excel)
        book_new.should be_a Book
        book_new.should be_alive
        book_new.should == @book2
      end

    end


  end
end
