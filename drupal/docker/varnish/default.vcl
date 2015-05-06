C{
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
}C

# Customized VCL file for serving a Drupal site.
# Wunderkraut / 2014

# Settings for a request that determines if web-01, web-02 or web-03 is alive and well.
probe healthcheck {
   .url = "/_ping.php";
   .interval = 5s;
   .timeout = 1s;
   .window = 5;
   .threshold = 3;
   .initial = 3;
   .expected_response = 200;
}

# Web backend definition.  Set this to point to your content server.
backend web1 {
  .host = "127.0.0.1";
  .port = "8080";
  .connect_timeout = 600s;
  .first_byte_timeout = 600s;
  .between_bytes_timeout = 600s;
  .probe = healthcheck;
}

# Define the director that determines how to distribute incoming requests.
director default_director round-robin {
  { .backend = web1; }
  #{ .backend = web2; }
  #{ .backend = web3; }
}

# Define the internal network access.
# These are used below to allow internal access to certain files
# from offices while not allowing access from the public internet.
acl internal {
  # localhost
  "127.0.0.1";
}

# List of upstream proxies we trust to set X-Forwarded-For correctly.
acl upstream_proxy {
  "127.0.0.1";
}

sub vcl_recv {
  C{
//
// This is a hack from Igor Gariev (gariev hotmail com):
// Copy IP address from "X-Forwarded-For" header
// into Varnish's client_ip structure.
// This works with Varnish 3.0.1; test with other versions
//
// Trusted "X-Forwarded-For" header is a must!
// No commas are allowed. If your load balancer something other
// than a single IP, then use a regsub() to fix it.
//
struct sockaddr_storage *client_ip_ss = VRT_r_client_ip(sp);
struct sockaddr_in *client_ip_si = (struct sockaddr_in *) client_ip_ss;
struct in_addr *client_ip_ia = &(client_ip_si->sin_addr);
char *xff_ip = VRT_GetHdr(sp, HDR_REQ, "\020X-Forwarded-For:");

if (xff_ip != NULL) {
// Copy the ip address into the struct's sin_addr.
inet_pton(AF_INET, xff_ip, client_ip_ia);
}
}C

  set req.backend = default_director;

  // Add a unique header containing the client address
  if (client.ip ~ upstream_proxy && req.http.X-Forwarded-For) {
    set req.http.X-Forwarded-For = req.http.X-Forwarded-For;
  } else {
    set req.http.X-Forwarded-For = client.ip;
  }

  if (req.request != "GET" && req.request != "HEAD") {
    /* We only deal with GET and HEAD by default */
    return (pass);
  }
  
  if (req.url == "/monit-check-url-happy") {
    error 200 "Varnish up";
  }
  
  # Healthy backend may be locked for 30s from request.
  # Sick may serve directly from cache for a few hours.
  if (req.backend.healthy) {
    set req.grace = 120s;
  }
  else {
    set req.grace = 2h;
  }

  // No varnish for ping file (for monitoring tools)
  if (req.url ~ "_ping.php") {
    return (pass);
  }

  if (req.url ~ "\.(png|gif|jpg|tif|tiff|ico|swf|css|js|pdf|doc|xls|ppt|zip)(\?.*)?$") {
    // Forcing a lookup with static file requests
    return (lookup);
  }

  # Do not allow public access to cron.php , update.php or install.php.
  if (req.url ~ "^/(cron|install|update)\.php$" && !client.ip ~ internal) {
    # Have Varnish throw the error directly.
    error 404 "Page not found.";
  }

  # Do not cache these paths.
  if (req.url ~ "^/update\.php$" ||
      req.url ~ "^/install\.php$" ||
      req.url ~ "^/cron\.php$" ||
      req.url ~ "^/ooyala/ping$" ||
      req.url ~ "^/admin/build/features" ||
      req.url ~ "^/info/.*$" ||
      req.url ~ "^/flag/.*$" ||
      req.url ~ "^.*/ajax/.*$" ||
      req.url ~ "^.*/ahah/.*$" ||
      req.url ~ "^/radioactivity_node.php$") {
       return (pass);
  }

  if (req.http.Cookie) {
    if (req.url ~ "\.(png|gif|jpg|tif|tiff|ico|swf|css|js|pdf|doc|xls|ppt|zip|woff|eot|ttf)$") {
      # Static file request do not vary on cookies
      unset req.http.Cookie;
    }
    elseif (req.http.Cookie ~ "(SESS[a-z0-9]+)") {
      # Authenticated users should not be cached
      return (pass);
    }
    else {
      # Remove all the cookies but the ones we need
      set req.http.Cookie = ";" + req.http.Cookie;
      set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
      set req.http.Cookie = regsuball(req.http.Cookie, ";(Drupal.visitor.Novita_user_store_country)=", "; \1=");
      set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
      set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

      if (req.http.Cookie == "") {
        /* If there are no remaining cookies, remove the cookie header. */
        unset req.http.Cookie;
      }
    }
  }

  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|png|gif|tif|tiff|ico|gz|tgz|bz2|tbz|mp3|ogg|swf|zip|pdf|woff|eot|ttf)(\?.*)?$") {
        # No point in compressing these
        unset req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
        set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
        set req.http.Accept-Encoding = "deflate";
    } else {
        # unkown algorithm
        unset req.http.Accept-Encoding;
    }
  }
  // Keep multiple cache objects to a minimum
  unset req.http.Accept-Language;
  unset req.http.user-agent;

}

sub vcl_fetch {

  # Store the request url in cached item
  # See "Smart banning" https://www.varnish-software.com/static/book/Cache_invalidation.html
  set beresp.http.x-url = req.url;
  
  # gzip is by default on for (easily) compressable transfer types
  if (beresp.http.content-type ~ "text/html" || beresp.http.content-type ~ "css" || beresp.http.content-type ~ "javascript") {
    set beresp.do_gzip = true;
  }

  # If Drupal page cache is enabled, it will send a X-Drupal-Cache header, and for anonoymous "Cache-Control: public, max-age=x."-headers.
  # In those cases, Varnish normally  uses the max-age value directly for do determine how long it is cached (ttl).
  # We can set the TTL for all content to 12h. Lets do it only if Varnish already thinks it is cacheable, and not a page-cache-item.
  if(beresp.status == 200 && beresp.ttl > 0s && !beresp.http.X-Drupal-Cache){
    # Default TTL for all content is 12h
    set beresp.ttl = 12h;
  }

  if (req.url ~ "\.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|pdf|txt|tar|wav|bmp|rtf|flv|swf|html|htm|otf|json)\??.*$") {
    # Strip any cookies before static files are inserted into cache.
    unset beresp.http.set-cookie;
    if(beresp.status == 200){
      set beresp.ttl = 7d;
      set beresp.http.isstatic = "1";
    } else{
      # Dont cache broken images etc for more than 30s, and not at all clientside.
      set beresp.ttl = 30s;
      set beresp.http.Cache-control = "max-age=0, must-revalidate";
    }
  }

  if (beresp.status == 404) {
    if (beresp.http.isstatic) {
      /*
       * 404s for static files might include profile data since they're actually Drupal pages.
       * See sites/default/settings.php for how 404s are implemented "the fast way"
       */
      set beresp.ttl = 0s;
    }
  }

  if (beresp.status >= 500 && beresp.status <= 505 && req.url !~ "DEBUG=true" && req.http.Cookie !~ "DEBUG=true") {
    # Make sure 50x errors are not served (except for 1s for URL-spam)
    set beresp.saintmode = 1s;
    if (req.restarts < 3 && req.request != "POST" && req.url !~ "\.(jpg|jpeg|gif|png)\??.*$"){
    # Re-sending POST-requests could mean trouble. We also dont want to restart failed image requests (it can create a lot of image_style spam).
    # Note that varnish default restart are limited to 3. Without a limit, we could easily create endless loops, basically DoS:ing ourselves.
      return(restart);
    } else {
      set beresp.ttl = 1s; // 2s cache.
      error beresp.status "Server Error";
    }
  }

  # Allow items to be stale if needed.
  set beresp.grace = 2h;

}

sub vcl_deliver {
  if (obj.hits > 0) {
    set resp.http.X-Varnish-Cache = "HIT";
  }
  else {
    set resp.http.X-Varnish-Cache = "MISS";
  }

  # See https://www.varnish-cache.org/trac/wiki/VCLExampleLongerCaching
  if (resp.http.magicmarker) {
    unset resp.http.magicmarker; # Remove the magic marker
    set resp.http.age = "0"; # By definition we have a fresh object
  }
 
  if (resp.http.isstatic) {
    unset resp.http.isstatic;
  }

  unset resp.http.X-Varnish;
  unset resp.http.Via;
  unset resp.http.Server;
  unset resp.http.X-Powered-By;
  unset resp.http.x-do-esi;
  unset resp.http.X-Forced-Gzip;
  unset resp.http.X-Generator;

  # Remove the request url from the cached item's headers
  # See "Smart banning" https://www.varnish-software.com/static/book/Cache_invalidation.html
  unset resp.http.x-url;
}

sub vcl_error {
  set obj.http.Content-Type = "text/html; charset=utf-8";
  if (obj.status == 401) {
    set obj.http.WWW-Authenticate = "Basic realm=Secured";
    synthetic {"
      <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
      "http://www.w3.org/TR/1999/REC-html401-19991224/loose.dtd">
      <HTML>
      <HEAD><TITLE>Error</TITLE><META HTTP-EQUIV='Content-Type' CONTENT='text/html;'>
        <link href="https://www.wunderkraut.fi/sites/default/files/error_page/style.css" rel="stylesheet" type="text/css">
      </HEAD>
      <BODY><div id="error-box"><div id="error-message"><H1>401 Unauthorized</H1></div></div></BODY>
      </HTML>
    "};
  }
  else {
    set obj.http.Retry-After = "10";
    synthetic {"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<link href="https://www.wunderkraut.fi/sites/default/files/error_page/style.css" rel="stylesheet" type="text/css">
<title>Error loading the page</title>

</head>

<body>
  <div id="error-box">
    &nbsp
    <div id="error-message">
      <h1>Our best people are on the case!</h1>
      <h2>Please check back shortly</h2>
      <h3>Error loading the page</h3>
    </div>
  </div>

  <script type="text/javascript">
    var _gaq = _gaq || [];
    _gaq.push(['_setAccount', 'SET_ACCOUNT_HERE']); _gaq.push(['_trackPageview']);
    _gaq.push(['_trackEvent', 'Errors', '"} + obj.status + {"', '"} + obj.response +
        " | " + req.http.X-Session-String + " | " + req.request + {" "']);
    (function() { var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true; ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js'; var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s); })();
  </script>
  <!--"} + obj.status + " " + obj.response + {"-->

</body>
</html>
"};
  }
  return (deliver);
}
sub vcl_hash {
  # add cookies to the has, we should only have store_country at this point left
  if (req.http.Cookie) {
    hash_data(req.http.Cookie);
  }
}
