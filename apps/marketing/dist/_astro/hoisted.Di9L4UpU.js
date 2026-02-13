import"./hoisted.d6V8J2CV.js";const n=document.getElementById("contact-form"),e=document.getElementById("contact-submit"),s=document.getElementById("contact-success");n?.addEventListener("submit",o=>{o.preventDefault();const t=document.getElementById("name").value,c=document.getElementById("email").value,m=document.getElementById("subject").value,d=document.getElementById("message").value,a=`Name: ${t}
Email: ${c}

${d}`,l=`mailto:hello@havenkeep.com?subject=${encodeURIComponent(m+" - "+t)}&body=${encodeURIComponent(a)}`;window.location.href=l,e&&e.classList.add("hidden"),s?.classList.remove("hidden"),setTimeout(()=>{n.reset(),e&&e.classList.remove("hidden"),s?.classList.add("hidden")},5e3)});
