# Matrix Notebook

## a project to use matrix as realtime scalable E2E encrypted content mangement system
https://github.com/user-attachments/assets/5e756e4d-9d8a-4d48-bf8d-fb89a1da0d2d


Try it out at https://matrix-notebook.pages.dev

# Planned Features

1. Publish your notes as a website

   Currently I am saving the notebook excatly like a filesystem

   you have a root node that will be the same for all users then each file and folder will be a under this node

   you can turn this tree into files each file is a rich text content currently its HTML you can use HTML -> Markdown libraries

2. Turn your notes into presentations

   I have done this before in another project its pretty easy using [Reveal JS](https://revealjs.com/)

3. Allow Rendering Custom File Types and Custom Nodes

   the idea is a simple to use plugin system just give the user the ability to link to a web component script and render it in the ui this ofc won't be safe so maybe we have a moderated repo for published plugins and we advice the user not to get their plugins anywhere else

4. Allow Viewing Diff And History Of The Notebook

   one amazing feature about loro is that it stores the history of the entire notebook that includes moving files and folders around aswell as each new addition and deletion in any file

   this means we have alot of info we can show about the state of this file since it was created for example

   also we can implement a git like system because loro support it but that will be a little more work i think so its not a big priority for now

   this feature is what i am talking about
   [Editorial workflows in Decap CMS](https://decapcms.org/docs/editorial-workflows/)

5. Offline collaboration  
   I am using Loro CRDT so offline work is already possible if you got disconnected from the internet and worked on a document next time you go back online it will sync and it will be saved in the room just need to make the app a PWA and it will just work

# state of the project : Alpha

this is the first working version of the project untill we reach beta its not adviced to use this app without backups of your data

your data is stored in one binary file you can inspect it using

[Loro Document Inspector](https://inspector.loro.dev/)

for example copy and paste this base64 string in the inspector above

[Base 64 String](./base-64.txt)
