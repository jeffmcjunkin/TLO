<%@ Page Language="C#" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Configuration" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        if (Session["auth"] == null) { Response.Redirect("Default.aspx"); }
    }

    protected void DoSearch(object sender, EventArgs e)
    {
        string q = txtQ.Text;
        string sql = "SELECT Name, Category, Price FROM dbo.Products WHERE Name LIKE '%" + q + "%'";
        var cs = ConfigurationManager.ConnectionStrings["AppDb"].ConnectionString;
        using (var con = new SqlConnection(cs))
        {
            con.Open();
            var da = new SqlDataAdapter(sql, con);
            var dt = new DataTable();
            try { da.Fill(dt); grid.DataSource = dt; grid.DataBind(); }
            catch (System.Exception ex) { lblErr.Text = ex.Message; }
        }
    }
</script>
<html>
<head><title>CorpShop - Product Search</title></head>
<body>
    <h2>Product Search</h2>
    <form id="form1" runat="server">
        <div>
            <asp:TextBox ID="txtQ" runat="server" />
            <asp:Button ID="btnSearch" Text="Search" OnClick="DoSearch" runat="server" />
            <asp:Label ID="lblErr" ForeColor="Red" runat="server" />
            <hr />
            <asp:GridView ID="grid" runat="server" />
        </div>
    </form>
</body>
</html>
