<%@ Page Language="C#" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Configuration" %>
<script runat="server">
    // CorpShop login. Uses parameterized queries.
    protected void DoLogin(object sender, EventArgs e)
    {
        var cs = ConfigurationManager.ConnectionStrings["AppDb"].ConnectionString;
        using (var con = new SqlConnection(cs))
        {
            con.Open();
            var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Users WHERE Username=@u AND Password=@p", con);
            cmd.Parameters.AddWithValue("@u", txtUser.Text);
            cmd.Parameters.AddWithValue("@p", txtPass.Text);
            int n = System.Convert.ToInt32(cmd.ExecuteScalar());
            if (n > 0) { Session["auth"] = txtUser.Text; Response.Redirect("Search.aspx"); }
            else { lblMsg.Text = "Invalid credentials"; }
        }
    }
</script>
<html>
<head><title>CorpShop - Login</title></head>
<body>
    <h2>CorpShop Internal Portal</h2>
    <form id="form1" runat="server">
        <div>
            Username: <asp:TextBox ID="txtUser" runat="server" /><br /><br />
            Password: <asp:TextBox ID="txtPass" TextMode="Password" runat="server" /><br /><br />
            <asp:Button ID="btnLogin" Text="Log in" OnClick="DoLogin" runat="server" />
            <asp:Label ID="lblMsg" ForeColor="Red" runat="server" />
        </div>
    </form>
</body>
</html>
