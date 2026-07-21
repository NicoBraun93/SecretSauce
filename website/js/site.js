/* ============================================================================
 * SECRETSAUCE SHOWCASE SITE SCRIPT
 * ----------------------------------------------------------------------------
 * Handles page scrolling effects and simple interaction scripts.
 * ==========================================================================*/

document.addEventListener('DOMContentLoaded', () => {
  initScrollHighlight();
});

/* ---- Simple Navbar Scroll Active Indicator -------------------------------- */
function initScrollHighlight() {
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav-links a');

  if (sections.length === 0 || navLinks.length === 0) return;

  window.addEventListener('scroll', () => {
    let current = '';
    
    sections.forEach(section => {
      const sectionTop = section.offsetTop;
      const sectionHeight = section.clientHeight;
      if (pageYOffset >= (sectionTop - 120)) {
        current = section.getAttribute('id');
      }
    });

    navLinks.forEach(link => {
      link.classList.remove('active');
      // Set link styling as active if href matches current ID
      const href = link.getAttribute('href').substring(1);
      if (href === current) {
        link.style.color = 'var(--fg-1)';
        link.style.background = 'hsl(var(--accent) / 0.6)';
      } else {
        link.style.color = '';
        link.style.background = '';
      }
    });
  });
}
