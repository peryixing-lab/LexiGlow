const fs = require('fs');
const path = require('path');
const sharp = require('/Users/thousandmiles/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const base = '/Users/thousandmiles/DevecostudioProjects/LexiGlow/exports/app-market-2026-10-09';
const pages = ['01-home.png','02-books.png','03-stats.png','04-profile.png'];
const labels = ['01 · 首页','02 · 词库','03 · 统计','04 · 我的'];
(async()=>{
  const width=1488, height=1480, margin=42, gap=18, tile=338;
  const rows=[
    {key:'phone',title:'手机  ·  9:16  ·  1080 × 1920',heading:124,top:150,h:601},
    {key:'tablet',title:'平板  ·  3:2  ·  1920 × 1280',heading:830,top:856,h:225},
    {key:'2in1',title:'2in1  ·  16:9  ·  1920 × 1080',heading:1160,top:1186,h:190}
  ];
  let svg='<svg xmlns="http://www.w3.org/2000/svg" width="'+width+'" height="'+height+'"><style>text{font-family:PingFang SC,Arial,sans-serif;fill:#242D29}.small{fill:#6C7469}</style><rect width="100%" height="100%" fill="#F6F2E4"/><text x="42" y="57" font-size="32" font-weight="600">词萤 · 应用市场宣传图</text><text x="42" y="84" font-size="17" class="small">让单词一点一点亮起来 · 三类设备 / 四个界面</text>';
  const composites=[];
  for(const row of rows){
    svg+='<text x="42" y="'+row.heading+'" font-size="19" font-weight="600">'+row.title+'</text>';
    for(let i=0;i<4;i++){
      const left=margin+i*(tile+gap);
      const thumb=await sharp(path.join(base,row.key,pages[i])).resize(tile,row.h,{fit:'contain'}).png().toBuffer();
      composites.push({input:thumb,left,top:row.top});
      svg+='<text x="'+left+'" y="'+(row.top+row.h+28)+'" font-size="16" class="small">'+labels[i]+'</text>';
    }
  }
  svg+='</svg>';
  await sharp(Buffer.from(svg)).composite(composites).png().toFile(path.join(base,'preview','overview.png'));
  console.log('Saved preview/overview.png');
})();
