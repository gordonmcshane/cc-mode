<!-- -*- html -*- -->
<?php
  $title = "Compatibility Notes";
  $menufiles = array ("links.h", "compatlinks.h");
  include ("header.h");
?>

<p>Setting up CC Mode is a little different for each version of XEmacs
and Emacs.  Users of Emacs 19.34 or NTEmacs 19.34, especially will
want to read the compatibility note for their version.

<ul>

  <li><a href="compat_xemacs.php">XEmacs and Emacs 20</a>

  <li><a href="compat_emacs19.php">Emacs 19</a>, specifically Emacs
  19.34.

  <li><a href="compat_emacs18.php">Emacs 18</a>

  <li><a href="compat_delbs_awk.php">Interactions with other Elisp
  packages</a>, e.g. <code>delbackspace.el</code> and
  <code>awk-mode</code>.

</ul>

<?php include ("footer.h"); ?>
