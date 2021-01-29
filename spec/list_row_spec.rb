# -*- coding: utf-8 -*-

require_relative 'spec_helper'

$VERBOSE = nil

include RobustExcelOle
include General

describe ListRow do
 
  before(:all) do
    excel = Excel.new(:reuse => true)
    open_books = excel == nil ? 0 : excel.Workbooks.Count
    puts "*** open books *** : #{open_books}" if open_books > 0
    Excel.kill_all
  end 

  before do
    @dir = create_tmpdir
    @listobject_file = @dir + '/workbook_listobjects.xlsx'
    @book = Workbook.open(@listobject_file, :visible => true)
    @sheet = @book.sheet(3)
  end

  after do
    @book.close(:if_unsaved => :forget)
    Excel.kill_all
    rm_tmp(@dir)
  end

  describe "to_a, to_h" do

    before do
      @table1 = @sheet.table(1)
    end

    it "should yield values of a row" do
      @table1[2].to_a.should == [2.0, "Fred", nil, 0.5416666666666666, 40]
      @table1[2].values.should == [2.0, "Fred", nil, 0.5416666666666666, 40]
    end

    it "should yield key-value pairs of a row" do
      @table[2].to_h.should == {"Number" => 2.0, "Person" => "Fred", "Amount" => nil, "Time" => 0.5416666666666666, "Price" => 40}
      @table[2].keys_values.should == {"Number" => 2.0, "Person" => "Fred", "Amount" => nil, "Time" => 0.5416666666666666, "Price" => 40}
    end

  end

  describe "getting and setting values" do

    context "with various column names" do

      context "with standard" do

        before do
          @table = Table.new(@sheet, "table_name", [12,1], 3, ["Person1","Win/Sales", "xiq-Xs", "OrderID", "YEAR", "length in m", "Amo%untSal___es"])
          @table_row1 = @table[1]
        end

        it "should read and set values via alternative column names" do
          @table_row1.person1.should be nil
          @table_row1.person1 = "John"
          @table_row1.person1.should == "John"
          @sheet[13,1].Value.should == "John"
          @table_row1.Person1 = "Herbert"
          @table_row1.Person1.should == "Herbert"
          @sheet[13,1].Value.should == "Herbert"
          @table_row1.win_sales.should be nil
          @table_row1.win_sales = 42
          @table_row1.win_sales.should == 42
          @sheet[13,2].Value.should == 42
          @table_row1.Win_Sales = 80
          @table_row1.Win_Sales.should == 80
          @sheet[13,2].Value.should == 80
          @table_row1.xiq_xs.should == nil
          @table_row1.xiq_xs = 90
          @table_row1.xiq_xs.should == 90
          @sheet[13,3].Value.should == 90
          @table_row1.xiq_Xs = 100
          @table_row1.xiq_Xs.should == 100
          @sheet[13,3].Value.should == 100
          @table_row1.order_id.should == nil
          @table_row1.order_id = 1
          @table_row1.order_id.should == 1
          @sheet[13,4].Value.should == 1
          @table_row1.OrderID = 2
          @table_row1.OrderID.should == 2
          @sheet[13,4].Value.should == 2
          @table_row1.year = 1984
          @table_row1.year.should == 1984
          @sheet[13,5].Value.should == 1984
          @table_row1.YEAR = 2020
          @table_row1.YEAR.should == 2020
          @sheet[13,5].Value.should == 2020
          @table_row1.length_in_m.should == nil
          @table_row1.length_in_m = 20
          @table_row1.length_in_m.should == 20
          @sheet[13,6].Value.should == 20
          @table_row1.length_in_m = 40
          @table_row1.length_in_m.should == 40
          @sheet[13,6].Value.should == 40
          @table_row1.amo_unt_sal___es.should == nil
          @table_row1.amo_unt_sal___es = 80
          @table_row1.amo_unt_sal___es.should == 80
          @sheet[13,7].Value.should == 80
        end

      end

      context "with umlauts" do

        before do
          @table = Table.new(@sheet, "table_name", [1,1], 3, ["Verkäufer", "Straße", "area in m²"])
          @table_row1 = @table[1]
        end

        it "should read and set values via alternative column names" do
          @table_row1.verkaeufer.should be nil
          @table_row1.verkaeufer = "John"
          @table_row1.verkaeufer.should == "John"
          @sheet[2,1].Value.should == "John"
          @table_row1.Verkaeufer = "Herbert"
          @table_row1.Verkaeufer.should == "Herbert"
          @sheet[2,1].Value.should == "Herbert"
          @table_row1.strasse.should be nil
          @table_row1.strasse = 42
          @table_row1.strasse.should == 42
          @sheet[2,2].Value.should == 42
          @table_row1.Strasse = 80
          @table_row1.Strasse.should == 80
          @sheet[2,2].Value.should == 80
          @table_row1.area_in_m3.should be nil
          @table_row1.area_in_m3 = 10
          @table_row1.area_in_m3.should == 10
          @sheet[2,3].Value.should == 10
        end

      end

    end

    context "with type-lifted ole list object" do

      before do
        ole_table = @sheet.ListObjects.Item(1)
        @table = Table.new(ole_table)
        @table_row1 = @table[1]
      end

      it "should set and read values" do
        @table_row1.number.should == 3
        @table_row1.number = 1
        @table_row1.number.should == 1
        @sheet[4,4].Value.should == 1
        @table_row1.person.should == "John"
        @table_row1.person = "Herbert"
        @table_row1.person.should == "Herbert"
        @sheet[4,5].Value.should == "Herbert"
      end
    end

  end

end
