\set t_pwd `pwd`

\set input_file '''':t_pwd'/Date_Dimension.tbl'''
COPY Date_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Product_Dimension.tbl'''
COPY Product_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Store_Dimension.tbl'''
COPY store.Store_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Promotion_Dimension.tbl'''
COPY Promotion_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Vendor_Dimension.tbl'''
COPY Vendor_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Customer_Dimension.tbl'''
COPY Customer_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Employee_Dimension.tbl'''
COPY Employee_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Warehouse_Dimension.tbl'''
COPY Warehouse_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Shipping_Dimension.tbl'''
COPY Shipping_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Online_Page_Dimension.tbl'''
COPY online_sales.Online_Page_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Call_Center_Dimension.tbl'''
COPY online_sales.Call_Center_Dimension FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Store_Sales_Fact_*.tbl'''
COPY store.Store_Sales_Fact FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Store_Orders_Fact_*.tbl'''
COPY store.Store_Orders_Fact FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Online_Sales_Fact_*.tbl'''
COPY online_sales.Online_Sales_Fact FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;

\set input_file '''':t_pwd'/Inventory_Fact_*.tbl'''
COPY Inventory_Fact FROM :input_file ON ANY NODE DELIMITER '|' NULL '' DIRECT;
