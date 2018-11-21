---
title: "Welcome to my new website"
date: 2018-11-20T01:15:40-05:00
---
### A quick introduction

I first launched my website on www.tdude.co in 2014 when I wanted a simple one-page website where I could list some of my work and my contact information for people who'd heard about me online and didn't really know anything about me.

I eventually expanded the site by adding some additional offering such as my [pomf file uploader](https://pomf.tdude.co) which is still available but the main page received very few updates at all.

As the years have past, I have accomplished many things and sometimes enjoy talking to my friends about them. On many occasions, it has been suggested to me that I should start a blog to post my findings for others to discover. I myself have learned a lot from various personal tech blogs I've sutmbled upon and thought this would be a great opportunity to launch my own. I want to share my knowledge and give back to the community that helped me by sharing it on my blog.

### About the tech stack of this blog

My old website accumulated a lot of technical debt in the sense that nothing was compartmentalized or templated, hundreds and thousands of lines of html and css in single files. It was difficult making adjustments to the site in a manageable way.

For the new site I decided to go with the [Hugo](https://gohugo.io) static site generator simply because I know other people using it and it works great. I actually had some trouble installing hugo on my ubuntu machine because it is developed at a rapid pace and the ubuntu packages for `cosmic` are already too out of date for my needs but everything is running smoothly with the hugo snapcraft package now! Other than that, it uses the [hyde-hyde](https://github.com/htr3n/hyde-hyde) theme and is automatically deployed using [Ansible](https://ansible.com) and [GitLab CI](https://about.gitlab.com/product/continuous-integration/).

The source code for the entire website is avaiable on my [GitHub](https://github.com/starcraft66/www.tdude.co)!